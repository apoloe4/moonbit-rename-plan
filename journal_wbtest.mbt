///|
test "journal requires intent then result and supports failed retry" {
  let plan = swapped()
  let step = plan.steps[0]
  let receipts = [
    step_receipt(step, "intent"),
    step_receipt(step, "failed"),
    step_receipt(step, "intent"),
    step_receipt(step, "completed"),
  ]
  let state = inspect_journal(plan, receipts)
  assert_true(state.valid)
  assert_eq(state.acknowledged, 1)
  assert_eq(state.attempts, 2)
  assert_eq(state.failures, 1)
}

///|
test "journal rejects completion without intent and interleaved intents" {
  let plan = swapped()
  let step = plan.steps[0]
  assert_false(inspect_journal(plan, [step_receipt(step, "completed")]).valid)
  assert_false(
    inspect_journal(plan, [
      step_receipt(step, "intent"),
      step_receipt(step, "intent"),
    ]).valid,
  )
  assert_false(
    inspect_journal(plan, [step_receipt(plan.steps[1], "intent")]).valid,
  )
  assert_false(inspect_journal(plan, [step_receipt(step, "unknown")]).valid)
}

///|
test "journal binds source destination and identity to planned step" {
  let plan = swapped()
  let receipt = step_receipt(plan.steps[0], "intent")
  for
    changed in [
      { ..receipt, source: "other", },
      { ..receipt, target: "other", },
      { ..receipt, identity: "other", },
    ] {
    assert_false(inspect_journal(plan, [changed]).valid)
  }
}

///|
test "pending intent before rename permits retry" {
  let plan = swapped()
  let result = reconcile_journal(
    plan,
    [step_receipt(plan.steps[0], "intent")],
    plan.initial,
  )
  assert_eq(result.status, "retry-pending")
  assert_eq(result.observedCompleted, Some(0))
}

///|
test "pending intent after rename requests missing completion receipt" {
  let plan = swapped()
  let result = reconcile_journal(
    plan,
    [step_receipt(plan.steps[0], "intent")],
    simulate(plan, 1).snapshot,
  )
  assert_eq(result.status, "acknowledge-pending")
  assert_eq(result.observedCompleted, Some(1))
  assert_eq(result.nextReceipt, Some(step_receipt(plan.steps[0], "completed")))
}

///|
test "journal disallows unrecorded operations without intent" {
  let plan = swapped()
  let result = reconcile_journal(plan, [], simulate(plan, 1).snapshot)
  assert_eq(result.status, "diverged")
  assert_eq(result.continueSteps, [])
}

///|
test "journal checkpoint resolves identical-content complete swap" {
  let plan = build_plan(
    [{ name: "a", identity: "same", }, { name: "b", identity: "same", }],
    [{ source: "a", target: "b", }, { source: "b", target: "a", }],
    Exact,
  )
  let receipts : Array[Receipt] = []
  for step in plan.steps {
    receipts.push(step_receipt(step, "intent"))
    receipts.push(step_receipt(step, "completed"))
  }
  assert_eq(recover(plan, plan.desired).status, "ambiguous")
  assert_eq(reconcile_journal(plan, receipts, plan.desired).status, "complete")
}

///|
test "all pending-intent windows of a cycle are resolved" {
  let plan = swapped()
  let receipts : Array[Receipt] = []
  for n, step in plan.steps {
    receipts.push(step_receipt(step, "intent"))
    assert_eq(
      reconcile_journal(plan, receipts, simulate(plan, n).snapshot).status,
      "retry-pending",
    )
    assert_eq(
      reconcile_journal(plan, receipts, simulate(plan, n + 1).snapshot).status,
      "acknowledge-pending",
    )
    receipts.push(step_receipt(step, "completed"))
  }
  assert_eq(reconcile_journal(plan, receipts, plan.desired).status, "complete")
  receipts.push(step_receipt(plan.steps[0], "intent"))
  assert_false(inspect_journal(plan, receipts).valid)
}

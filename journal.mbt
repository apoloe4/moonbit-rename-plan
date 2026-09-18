///|
/// Intent/result pairs form a caller-persisted logical journal. The planner does
/// not write this journal and does not assert that it was durably flushed.
pub(all) struct Receipt {
  step : Int
  source : String
  target : String
  identity : String
  event : String
} derive(Eq, Debug, ToJson)

///|
pub(all) struct JournalState {
  valid : Bool
  acknowledged : Int
  pending : Bool
  attempts : Int
  failures : Int
  errors : Array[String]
} derive(Eq, Debug, ToJson)

///|
/// Require an intent before each completed/failed result. Failed steps may be
/// retried; completed steps may not be repeated or silently skipped.
pub fn inspect_journal(plan : Plan, receipts : Array[Receipt]) -> JournalState {
  let errors : Array[String] = []
  let mut acknowledged = 0
  let mut pending = false
  let mut attempts = 0
  let mut failures = 0
  if !plan.problems.is_empty() {
    errors.push("plan is blocked")
  }
  if receipts.length() > 8000 {
    errors.push("journal limit is 8000 receipts")
  }
  if !errors.is_empty() {
    return { valid: false, acknowledged, pending, attempts, failures, errors, }
  }
  for position, receipt in receipts {
    if acknowledged >= plan.steps.length() {
      errors.push("receipt \{position}: journal continues after final step")
      break
    }
    let step = plan.steps[acknowledged]
    if receipt.step != acknowledged ||
      receipt.source != step.source ||
      receipt.target != step.target ||
      receipt.identity != step.identity {
      errors.push(
        "receipt \{position}: does not match next planned step \{acknowledged}",
      )
      break
    }
    match receipt.event {
      "intent" => {
        if pending {
          errors.push("receipt \{position}: previous intent has no result")
          break
        }
        pending = true
        attempts = attempts + 1
      }
      "completed" => {
        if !pending {
          errors.push("receipt \{position}: completed without intent")
          break
        }
        acknowledged = acknowledged + 1
        pending = false
      }
      "failed" => {
        if !pending {
          errors.push("receipt \{position}: failed without intent")
          break
        }
        failures = failures + 1
        pending = false
      }
      _ => {
        errors.push("receipt \{position}: unknown event")
        break
      }
    }
  }
  {
    valid: errors.is_empty(),
    acknowledged,
    pending,
    attempts,
    failures,
    errors,
  }
}

///|
pub fn step_receipt(step : Step, event : String) -> Receipt {
  {
    step: step.index,
    source: step.source,
    target: step.target,
    identity: step.identity,
    event,
  }
}

///|
pub(all) struct Reconciliation {
  status : String
  acknowledged : Int
  observedCompleted : Int?
  nextReceipt : Receipt?
  continueSteps : Array[Step]
  rollback : Array[Step]
  differences : Array[Difference]
  errors : Array[String]
} derive(Eq, Debug, ToJson)

///|
/// Resolve the crash window between a rename and its result receipt. An open
/// intent permits exactly two possible namespaces (before or after that step).
/// This is a logical model assuming reliable identities and a trusted journal.
pub fn reconcile_journal(
  plan : Plan,
  receipts : Array[Receipt],
  observed : Array[Entry],
) -> Reconciliation raise PlanningError {
  let state = inspect_journal(plan, receipts)
  if !state.valid {
    return {
      status: "invalid-journal",
      acknowledged: state.acknowledged,
      observedCompleted: None,
      nextReceipt: None,
      continueSteps: [],
      rollback: [],
      differences: [],
      errors: state.errors,
    }
  }
  if !validate_request(observed, [], plan.policy).is_empty() {
    raise Invalid("invalid observed snapshot")
  }
  let before = simulate(plan, state.acknowledged)
  let before_diff = snapshot_diff(before.snapshot, observed)
  if before_diff.is_empty() {
    return {
      status: if state.pending {
        "retry-pending"
      } else if state.acknowledged == plan.steps.length() {
        "complete"
      } else {
        "consistent"
      },
      acknowledged: state.acknowledged,
      observedCompleted: Some(state.acknowledged),
      nextReceipt: None,
      continueSteps: before.remaining,
      rollback: before.rollback,
      differences: [],
      errors: [],
    }
  }
  if state.pending {
    let after = simulate(plan, state.acknowledged + 1)
    let after_diff = snapshot_diff(after.snapshot, observed)
    if after_diff.is_empty() {
      return {
        status: "acknowledge-pending",
        acknowledged: state.acknowledged,
        observedCompleted: Some(state.acknowledged + 1),
        nextReceipt: Some(
          step_receipt(plan.steps[state.acknowledged], "completed"),
        ),
        continueSteps: after.remaining,
        rollback: after.rollback,
        differences: [],
        errors: [],
      }
    }
    return {
      status: "diverged",
      acknowledged: state.acknowledged,
      observedCompleted: None,
      nextReceipt: None,
      continueSteps: [],
      rollback: [],
      differences: if after_diff.length() < before_diff.length() {
        after_diff
      } else {
        before_diff
      },
      errors: [],
    }
  }
  {
    status: "diverged",
    acknowledged: state.acknowledged,
    observedCompleted: None,
    nextReceipt: None,
    continueSteps: [],
    rollback: [],
    differences: before_diff,
    errors: [],
  }
}

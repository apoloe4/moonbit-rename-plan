///|
pub(all) struct Recovery {
  status : String
  matchingPrefixes : Array[Int]
  nearestPrefix : Int
  differences : Array[Difference]
  continueSteps : Array[Step]
  rollback : Array[Step]
} derive(Eq, Debug, ToJson)

///|
/// Match the complete observed namespace to every legal step boundary.
/// Multiple matches (e.g. swapping equal-content files) are explicitly ambiguous.
pub fn recover(
  plan : Plan,
  observed : Array[Entry],
) -> Recovery raise PlanningError {
  if !plan.problems.is_empty() {
    raise Invalid("cannot recover blocked plan")
  }
  let validation = validate_request(observed, [], plan.policy)
  if !validation.is_empty() {
    raise Invalid("invalid observed snapshot: \{validation[0].code}")
  }
  let matches : Array[Int] = []
  let mut state = plan.initial
  let mut nearest = 0
  let mut nearest_diff = snapshot_diff(state, observed)
  for boundary = 0; boundary <= plan.steps.length(); boundary = boundary + 1 {
    let differences = snapshot_diff(state, observed)
    if differences.is_empty() {
      matches.push(boundary)
    }
    if differences.length() < nearest_diff.length() {
      nearest = boundary
      nearest_diff = differences
    }
    if boundary < plan.steps.length() {
      state = replay(state, [plan.steps[boundary]], plan.policy)
    }
  }
  if matches.length() != 1 {
    return {
      status: if matches.is_empty() {
        "diverged"
      } else {
        "ambiguous"
      },
      matchingPrefixes: matches,
      nearestPrefix: nearest,
      differences: nearest_diff,
      continueSteps: [],
      rollback: [],
    }
  }
  let completed = matches[0]
  let simulation = simulate(plan, completed)
  {
    status: if completed == plan.steps.length() {
      "complete"
    } else {
      "resumable"
    },
    matchingPrefixes: matches,
    nearestPrefix: completed,
    differences: [],
    continueSteps: simulation.remaining,
    rollback: simulation.rollback,
  }
}

///|
pub(all) struct BoundaryCheck {
  completed : Int
  forwardOk : Bool
  rollbackOk : Bool
} derive(Eq, Debug, ToJson)

///|
/// Exhaustively verify every successful-step boundary in the logical model.
/// This is not a proof of crash atomicity, fsync behavior or external executors.
pub fn verify_boundaries(
  plan : Plan,
) -> Array[BoundaryCheck] raise PlanningError {
  if plan.steps.length() > 200 {
    raise Invalid(
      "exhaustive verification limited to 200 steps; simulate individual boundaries for larger plans",
    )
  }
  let result : Array[BoundaryCheck] = []
  for count = 0; count <= plan.steps.length(); count = count + 1 {
    let sim = simulate(plan, count)
    let restored = replay(sim.snapshot, sim.rollback, plan.policy)
    let finished = replay(sim.snapshot, sim.remaining, plan.policy)
    // Recovery is tested separately; avoid a quadratic recovery sweep per prefix.
    result.push({
      completed: count,
      forwardOk: snapshot_diff(plan.desired, finished).is_empty(),
      rollbackOk: snapshot_diff(plan.initial, restored).is_empty(),
    })
  }
  result
}

///|
/// Use an externally trusted completed-step checkpoint to resolve equal-identity
/// ambiguity. The entire observed namespace still has to match that boundary.
pub fn recover_from_checkpoint(
  plan : Plan,
  observed : Array[Entry],
  completed : Int,
) -> Recovery raise PlanningError {
  let validation = validate_request(observed, [], plan.policy)
  if !validation.is_empty() {
    raise Invalid("invalid observed snapshot")
  }
  let sim = simulate(plan, completed)
  let differences = snapshot_diff(sim.snapshot, observed)
  if !differences.is_empty() {
    return {
      status: "diverged",
      matchingPrefixes: [],
      nearestPrefix: completed,
      differences,
      continueSteps: [],
      rollback: [],
    }
  }
  {
    status: if completed == plan.steps.length() {
      "complete"
    } else {
      "resumable"
    },
    matchingPrefixes: [completed],
    nearestPrefix: completed,
    differences: [],
    continueSteps: sim.remaining,
    rollback: sim.rollback,
  }
}

///|
pub(all) struct PlanAudit {
  valid : Bool
  errors : Array[String]
} derive(Eq, Debug, ToJson)

///|
/// Validate public Plan values supplied by library consumers, not just generated
/// ones. No operation is performed on disk; this checks the logical contract.
pub fn audit_plan(plan : Plan) -> PlanAudit {
  let errors : Array[String] = []
  if !plan.problems.is_empty() {
    errors.push("blocked plan")
  }
  for i, step in plan.steps {
    if step.index != i {
      errors.push("nonsequential step index at \{i}")
    }
  }
  try {
    let result = replay(plan.initial, plan.steps, plan.policy)
    if !snapshot_diff(plan.desired, result).is_empty() {
      errors.push("final namespace differs from declared desired state")
    }
    let restored = replay(result, reverse_steps(plan.steps), plan.policy)
    if !snapshot_diff(plan.initial, restored).is_empty() {
      errors.push("reverse sequence does not restore original namespace")
    }
  } catch {
    Invalid(message) => errors.push(message)
  }
  { valid: errors.is_empty(), errors, }
}

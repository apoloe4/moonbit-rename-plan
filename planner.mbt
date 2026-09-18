///|
priv struct Pending {
  mut source : String
  target : String
  identity : String
  mut done : Bool
  mut staged : Bool
}

///|
/// Produce a deterministic plan. Free sinks are processed first; each blocked
/// cycle is opened by parking one entry in a fresh temporary name.
pub fn build_plan(
  entries : Array[Entry],
  mappings : Array[Rename],
  policy : NamePolicy,
) -> Plan {
  let problems = validate_request(entries, mappings, policy)
  let initial = sorted_entries(entries)
  if !problems.is_empty() {
    return {
      policy,
      initial,
      desired: initial,
      steps: [],
      problems,
      skipped: 0,
      temporaryNames: [],
    }
  }
  let ordered = mappings.copy()
  ordered.sort_by(fn(a, b) { a.source.lexical_compare(b.source) })
  let occupied : Map[String, Entry] = Map([])
  let reserved : Map[String, Bool] = Map([])
  let requested : Map[String, String] = Map([])
  for entry in initial {
    occupied[name_key(entry.name, policy)] = entry
    reserved[name_key(entry.name, policy)] = true
  }
  let pending : Array[Pending] = []
  let mut skipped = 0
  for mapping in ordered {
    requested[mapping.source] = mapping.target
    reserved[name_key(mapping.target, policy)] = true
    if mapping.source == mapping.target {
      skipped = skipped + 1
      continue
    }
    pending.push({
      source: mapping.source,
      target: mapping.target,
      identity: occupied[name_key(mapping.source, policy)].identity,
      done: false,
      staged: false,
    })
  }
  let desired : Array[Entry] = []
  for entry in initial {
    desired.push({
      name: requested.get(entry.name).unwrap_or(entry.name),
      identity: entry.identity,
    })
  }
  let steps : Array[Step] = []
  let temps : Array[String] = []
  let mut remaining = pending.length()
  let mut sequence = 1
  while remaining > 0 {
    let mut progressed = false
    for task in pending {
      if task.done {
        continue
      }
      let dst = name_key(task.target, policy)
      if !occupied.contains(dst) {
        steps.push({
          index: steps.length(),
          source: task.source,
          target: task.target,
          identity: task.identity,
          reason: if task.staged {
            "release"
          } else {
            "direct"
          },
        })
        occupied.remove(name_key(task.source, policy))
        occupied[dst] = { name: task.target, identity: task.identity, }
        task.done = true
        remaining = remaining - 1
        progressed = true
      }
    }
    if progressed {
      continue
    }
    // All targets are occupied by active sources: a cycle (possibly case-only).
    for task in pending {
      if task.done {
        continue
      }
      let mut candidate = ".moonrename-tmp-\{sequence}"
      while reserved.contains(name_key(candidate, policy)) {
        sequence = sequence + 1
        candidate = ".moonrename-tmp-\{sequence}"
      }
      sequence = sequence + 1
      reserved[name_key(candidate, policy)] = true
      temps.push(candidate)
      steps.push({
        index: steps.length(),
        source: task.source,
        target: candidate,
        identity: task.identity,
        reason: "park",
      })
      occupied.remove(name_key(task.source, policy))
      occupied[name_key(candidate, policy)] = {
        name: candidate,
        identity: task.identity,
      }
      task.source = candidate
      task.staged = true
      break
    }
  }
  {
    policy,
    initial,
    desired: sorted_entries(desired),
    steps,
    problems: [],
    skipped,
    temporaryNames: temps,
  }
}

///|
/// Graph components explain why a chain requires ordering or a cycle needs a
/// parking name. This graph is derived from requested names, not emitted steps.
pub(all) struct Component {
  kind : String
  sources : Array[String]
} derive(Eq, Debug, ToJson)

///|
pub fn dependency_components(
  mappings : Array[Rename],
  policy : NamePolicy,
) -> Array[Component] {
  let graph : Map[String, String] = Map([])
  let originals : Map[String, String] = Map([])
  for mapping in mappings {
    if mapping.source != mapping.target {
      let key = name_key(mapping.source, policy)
      graph[key] = name_key(mapping.target, policy)
      originals[key] = mapping.source
    }
  }
  let keys = graph.keys().to_array()
  keys.sort_by(fn(a, b) { a.lexical_compare(b) })
  let visited : Map[String, Bool] = Map([])
  let result : Array[Component] = []
  for key in keys {
    if visited.contains(key) {
      continue
    }
    // Find the head by following reverse edges (unique targets after preflight).
    let mut head = key
    let backward : Map[String, Bool] = Map([])
    while !backward.contains(head) {
      backward[head] = true
      let mut predecessor : String? = None
      for candidate in keys {
        if graph[candidate] == head {
          predecessor = Some(candidate)
          break
        }
      }
      match predecessor {
        Some(prev) => head = prev
        None => break
      }
    }
    let mut cursor = head
    let path : Array[String] = []
    let seen_path : Map[String, Bool] = Map([])
    let mut cyclic = false
    while graph.contains(cursor) {
      if seen_path.contains(cursor) {
        cyclic = true
        break
      }
      if visited.contains(cursor) {
        break
      }
      seen_path[cursor] = true
      visited[cursor] = true
      path.push(originals[cursor])
      cursor = graph[cursor]
    }
    if !path.is_empty() {
      let kind = if cyclic {
        if path.length() == 1 {
          "case-only"
        } else {
          "cycle"
        }
      } else {
        "chain"
      }
      result.push({ kind, sources: path, })
    }
  }
  result
}

///|
pub(all) struct Simulation {
  completed : Int
  snapshot : Array[Entry]
  remaining : Array[Step]
  rollback : Array[Step]
} derive(Eq, Debug, ToJson)

///|
/// Replay guarded logical rename steps. Nothing in this library accesses disk.
/// Both exact source spelling/identity and destination absence are required.
pub fn replay(
  entries : Array[Entry],
  steps : Array[Step],
  policy : NamePolicy,
) -> Array[Entry] raise PlanningError {
  let problems = validate_request(entries, [], policy)
  if !problems.is_empty() {
    raise Invalid("invalid snapshot: \{problems[0].code}")
  }
  let state : Map[String, Entry] = Map([])
  for entry in entries {
    state[name_key(entry.name, policy)] = entry
  }
  for step in steps {
    if filename_problem(step.source) != None ||
      filename_problem(step.target) != None {
      raise Invalid("invalid step filename")
    }
    let src = name_key(step.source, policy)
    let dst = name_key(step.target, policy)
    let entry = match state.get(src) {
      Some(entry) => entry
      None =>
        raise Invalid("step \{step.index}: source missing: \{step.source}")
    }
    if entry.name != step.source || entry.identity != step.identity {
      raise Invalid("step \{step.index}: source spelling or identity changed")
    }
    if state.contains(dst) {
      raise Invalid("step \{step.index}: target occupied: \{step.target}")
    }
    state.remove(src)
    state[dst] = { name: step.target, identity: entry.identity, }
  }
  sorted_entries(state.values().to_array())
}

///|
pub fn reverse_steps(steps : Array[Step]) -> Array[Step] {
  let result : Array[Step] = []
  for i = steps.length() - 1; i >= 0; i = i - 1 {
    let step = steps[i]
    result.push({
      index: result.length(),
      source: step.target,
      target: step.source,
      identity: step.identity,
      reason: "rollback",
    })
  }
  result
}

///|
/// Inspect the boundary after exactly `completed` successful renames.
pub fn simulate(plan : Plan, completed : Int) -> Simulation raise PlanningError {
  if !plan.problems.is_empty() {
    raise Invalid("cannot simulate blocked plan")
  }
  if completed < 0 || completed > plan.steps.length() {
    raise Invalid("completed step count out of bounds")
  }
  let prefix : Array[Step] = []
  let remaining : Array[Step] = []
  for i, step in plan.steps {
    if i < completed {
      prefix.push(step)
    } else {
      remaining.push(step)
    }
  }
  let snapshot = replay(plan.initial, prefix, plan.policy)
  { completed, snapshot, remaining, rollback: reverse_steps(prefix), }
}

///|
pub(all) struct Difference {
  kind : String
  name : String
  expected : String
  observed : String
} derive(Eq, Debug, ToJson)

///|
/// Exact names are compared so a case-only rename is visible even under folding.
pub fn snapshot_diff(
  expected : Array[Entry],
  observed : Array[Entry],
) -> Array[Difference] {
  let expected_map : Map[String, String] = Map([])
  let observed_map : Map[String, String] = Map([])
  for entry in expected {
    expected_map[entry.name] = entry.identity
  }
  for entry in observed {
    observed_map[entry.name] = entry.identity
  }
  let differences : Array[Difference] = []
  for entry in sorted_entries(expected) {
    match observed_map.get(entry.name) {
      None =>
        differences.push({
          kind: "missing",
          name: entry.name,
          expected: entry.identity,
          observed: "",
        })
      Some(identity) if identity != entry.identity =>
        differences.push({
          kind: "identity_changed",
          name: entry.name,
          expected: entry.identity,
          observed: identity,
        })
      _ => ()
    }
  }
  for entry in sorted_entries(observed) {
    if !expected_map.contains(entry.name) {
      differences.push({
        kind: "unexpected",
        name: entry.name,
        expected: "",
        observed: entry.identity,
      })
    }
  }
  differences
}

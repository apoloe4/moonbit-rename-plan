///|
fn object(
  json : Json,
  context : String,
) -> Map[String, Json] raise PlanningError {
  match json {
    Object(o) => o
    _ => raise Invalid("\{context} must be an object")
  }
}

///|
fn only_keys(
  obj : Map[String, Json],
  keys : Array[String],
) -> Unit raise PlanningError {
  for key, _ in obj {
    if !keys.contains(key) {
      raise Invalid("unknown field: \{key}")
    }
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise PlanningError {
  match obj.get(key) {
    Some(String(s)) => s
    _ => raise Invalid("\{key} must be a string")
  }
}

///|
fn optional_string(
  obj : Map[String, Json],
  key : String,
) -> String? raise PlanningError {
  match obj.get(key) {
    None => None
    Some(String(s)) => Some(s)
    _ => raise Invalid("\{key} must be a string when supplied")
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise PlanningError {
  match obj.get(key) {
    Some(Array(items)) => items
    _ => raise Invalid("\{key} must be an array")
  }
}

///|
fn optional_int(
  obj : Map[String, Json],
  key : String,
) -> Int? raise PlanningError {
  match obj.get(key) {
    None => None
    Some(Number(n, ..)) if !n.is_nan() &&
      !n.is_inf() &&
      n >= 0.0 &&
      n <= 1000000.0 &&
      n == n.to_int().to_double() => Some(n.to_int())
    _ => raise Invalid("\{key} must be a nonnegative integer <= 1000000")
  }
}

///|
fn decode_entries(json : Json) -> Array[Entry] raise PlanningError {
  let items = match json {
    Array(items) => items
    _ => raise Invalid("snapshot must be an array")
  }
  if items.length() > 1000 {
    raise Invalid("snapshot limit is 1000 entries")
  }
  let entries : Array[Entry] = []
  for item in items {
    let o = object(item, "entry")
    only_keys(o, ["name", "identity"])
    entries.push({
      name: required_string(o, "name"),
      identity: required_string(o, "identity"),
    })
  }
  entries
}

///|
fn decode_policy(obj : Map[String, Json]) -> NamePolicy raise PlanningError {
  match optional_string(obj, "policy").unwrap_or("exact") {
    "exact" => Exact
    "ascii-fold" => AsciiFold
    _ => raise Invalid("policy must be exact or ascii-fold")
  }
}

///|
fn decode_mappings(items : Array[Json]) -> Array[Rename] raise PlanningError {
  if items.length() > 1000 {
    raise Invalid("mapping limit is 1000")
  }
  let mappings : Array[Rename] = []
  for item in items {
    let o = object(item, "mapping")
    only_keys(o, ["source", "target"])
    mappings.push({
      source: required_string(o, "source"),
      target: required_string(o, "target"),
    })
  }
  mappings
}

///|
fn decode_rule(json : Json) -> NameRule raise PlanningError {
  let obj = object(json, "rule")
  only_keys(obj, [
    "prefix", "suffix", "find", "replacement", "extension", "sequenceStart", "sequenceWidth",
    "onlySuffix", "caseMode",
  ])
  {
    prefix: optional_string(obj, "prefix").unwrap_or(""),
    suffix: optional_string(obj, "suffix").unwrap_or(""),
    find: optional_string(obj, "find").unwrap_or(""),
    replacement: optional_string(obj, "replacement").unwrap_or(""),
    extension: optional_string(obj, "extension"),
    sequenceStart: optional_int(obj, "sequenceStart"),
    sequenceWidth: optional_int(obj, "sequenceWidth").unwrap_or(3),
    onlySuffix: optional_string(obj, "onlySuffix"),
    caseMode: optional_string(obj, "caseMode").unwrap_or("keep"),
  }
}

///|
fn decode_request(
  text : String,
) -> (Plan, Array[Rename], Map[String, Json]) raise {
  if text.length() > 2000000 {
    raise Invalid("request exceeds 2 million UTF-16 units")
  }
  let obj = object(@json.parse(text), "request")
  only_keys(obj, [
    "entries", "mappings", "policy", "rule", "completed", "verify",
  ])
  let entries = decode_entries(required_array(obj, "entries").to_json())
  let policy = decode_policy(obj)
  let mappings = match obj.get("rule") {
    Some(rule) => {
      if obj.contains("mappings") {
        raise Invalid("provide rule or mappings, not both")
      }
      generate_mappings(entries, decode_rule(rule))
    }
    None => decode_mappings(required_array(obj, "mappings"))
  }
  (build_plan(entries, mappings, policy), mappings, obj)
}

///|
fn plan_value(plan : Plan, mappings : Array[Rename]) -> Json {
  let safe = plan.problems.is_empty()
  let components = if safe {
    dependency_components(mappings, plan.policy)
  } else {
    []
  }
  {
    "format": "moonrename-plan/v1",
    "status": (if safe { "ready" } else { "blocked" }).to_json(),
    "policy": (if plan.policy == Exact { "exact" } else { "ascii-fold" }).to_json(),
    "initial": plan.initial.to_json(),
    "desired": plan.desired.to_json(),
    "mappings": mappings.to_json(),
    "steps": plan.steps.to_json(),
    "problems": plan.problems.to_json(),
    "skipped": plan.skipped.to_json(),
    "temporaryNames": plan.temporaryNames.to_json(),
    "components": components.to_json(),
    "stepCount": plan.steps.length().to_json(),
    "markdown": render_markdown(plan).to_json(),
    "dot": render_dot(plan).to_json(),
    "audit": ToJson::to_json(audit_plan(plan)),
  }
}

///|
fn error_value(message : String) -> String {
  let value : Json = { "status": "error", "message": message.to_json() }
  value.stringify()
}

///|
/// FFI entry: strict request validation, planning and optional prefix simulation.
pub fn plan_json(request : String) -> String {
  try {
    let (plan, mappings, obj) = decode_request(request)
    let out = object(plan_value(plan, mappings), "internal plan")
    let completed = optional_int(obj, "completed")
    let verify = match obj.get("verify") {
      None | Some(False) => false
      Some(True) => true
      _ => raise Invalid("verify must be boolean")
    }
    if plan.problems.is_empty() {
      match completed {
        Some(count) =>
          out["simulation"] = ToJson::to_json(simulate(plan, count))
        None => ()
      }
      if verify {
        out["boundaries"] = verify_boundaries(plan).to_json()
      }
    }
    out.to_json().stringify()
  } catch {
    e => error_value(e.to_string())
  }
}

///|
/// Recovery always regenerates the deterministic plan from the original request;
/// serialized step arrays are never trusted as executable instructions.
pub fn recover_json(request : String, observed_json : String) -> String {
  try {
    let (plan, _, _) = decode_request(request)
    if observed_json.length() > 2000000 {
      raise Invalid("snapshot too large")
    }
    let observed = decode_entries(@json.parse(observed_json))
    ToJson::to_json(recover(plan, observed)).stringify()
  } catch {
    e => error_value(e.to_string())
  }
}

///|
/// Preview rule expansion through the same preflight/plan pipeline.
pub fn rules_json(request : String) -> String {
  plan_json(request)
}

///|
/// JSON adapter for externally persisted intent/result journals.
pub fn journal_json(
  request : String,
  receipts_json : String,
  observed_json : String,
) -> String {
  try {
    let (plan, _, _) = decode_request(request)
    if receipts_json.length() > 2000000 || observed_json.length() > 2000000 {
      raise Invalid("journal or snapshot too large")
    }
    let items = match @json.parse(receipts_json) {
      Array(items) => items
      _ => raise Invalid("journal must be an array")
    }
    if items.length() > 8000 {
      raise Invalid("journal limit is 8000 receipts")
    }
    let receipts : Array[Receipt] = []
    for item in items {
      let obj = object(item, "receipt")
      only_keys(obj, ["step", "source", "target", "identity", "event"])
      let step = match optional_int(obj, "step") {
        Some(n) => n
        None => raise Invalid("receipt requires step")
      }
      receipts.push({
        step,
        source: required_string(obj, "source"),
        target: required_string(obj, "target"),
        identity: required_string(obj, "identity"),
        event: required_string(obj, "event"),
      })
    }
    let observed = decode_entries(@json.parse(observed_json))
    ToJson::to_json(reconcile_journal(plan, receipts, observed)).stringify()
  } catch {
    e => error_value(e.to_string())
  }
}

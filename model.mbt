///|
/// A name and an opaque identity. Identical identities are allowed: recovery
/// then reports ambiguity rather than guessing which indistinguishable file moved.
pub(all) struct Entry {
  name : String
  identity : String
} derive(Eq, Debug, ToJson)

///|
pub(all) struct Rename {
  source : String
  target : String
} derive(Eq, Debug, ToJson)

///|
/// AsciiFold folds A-Z only; it is not a model of Unicode NTFS/APFS collation.
pub(all) enum NamePolicy {
  Exact
  AsciiFold
} derive(Eq, Debug)

///|
pub(all) struct Problem {
  code : String
  name : String
  detail : String
} derive(Eq, Debug, ToJson)

///|
pub(all) struct Step {
  index : Int
  source : String
  target : String
  identity : String
  reason : String
} derive(Eq, Debug, ToJson)

///|
pub(all) struct Plan {
  policy : NamePolicy
  initial : Array[Entry]
  desired : Array[Entry]
  steps : Array[Step]
  problems : Array[Problem]
  skipped : Int
  temporaryNames : Array[String]
} derive(Debug)

///|
pub(all) suberror PlanningError {
  Invalid(String)
}

///|
pub fn name_key(name : String, policy : NamePolicy) -> String {
  if policy == Exact {
    return name
  }
  let out = StringBuilder()
  for ch in name.iter() {
    if ch >= 'A' && ch <= 'Z' {
      out.write_char((ch.to_int() + 32).unsafe_to_char())
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// Flat portable filename validation. These deliberately conservative rules
/// reject separators, dot paths, control characters and Windows device names.
pub fn filename_problem(name : String) -> String? {
  if name.is_empty() {
    return Some("empty filename")
  }
  let chars = name.iter().to_array()
  if chars.length() > 180 {
    return Some("filename exceeds 180 Unicode scalars")
  }
  if name == "." || name == ".." {
    return Some("dot paths are not filenames")
  }
  let last = chars[chars.length() - 1]
  if last == '.' || last == ' ' {
    return Some("trailing dot or space is not portable")
  }
  for c in chars {
    if c.to_int() < 32 ||
      c.to_int() == 127 ||
      ['/', '\\', ':', '*', '?', '"', '<', '>', '|'].contains(c) {
      return Some("path separator, control character or reserved punctuation")
    }
  }
  let base = StringBuilder()
  for c in chars {
    if c == '.' {
      break
    }
    base.write_char(c)
  }
  let stem = name_key(base.to_string(), AsciiFold)
  if [
      "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6",
      "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7",
      "lpt8", "lpt9",
    ].contains(stem) {
    return Some("reserved portable device name")
  }
  None
}

///|
fn sorted_entries(entries : Array[Entry]) -> Array[Entry] {
  let result = entries.copy()
  result.sort_by(fn(a, b) { a.name.lexical_compare(b.name) })
  result
}

///|
fn issue(code : String, name : String, detail : String) -> Problem {
  { code, name, detail, }
}

///|
/// Collect all independent preflight errors; do not silently discard mappings.
pub fn validate_request(
  entries : Array[Entry],
  moves : Array[Rename],
  policy : NamePolicy,
) -> Array[Problem] {
  let errors : Array[Problem] = []
  if entries.length() > 1000 || moves.length() > 1000 {
    return [issue("limit", "", "at most 1000 entries and 1000 mappings")]
  }
  let existing : Map[String, String] = Map([])
  let sources : Map[String, String] = Map([])
  let targets : Map[String, String] = Map([])
  for entry in entries {
    match filename_problem(entry.name) {
      Some(detail) => errors.push(issue("invalid_name", entry.name, detail))
      None => ()
    }
    if entry.identity.is_empty() || entry.identity.length() > 512 {
      errors.push(
        issue(
          "identity",
          entry.name,
          "identity must contain 1..512 UTF-16 units",
        ),
      )
    }
    let key = name_key(entry.name, policy)
    match existing.get(key) {
      Some(other) =>
        errors.push(issue("snapshot_collision", entry.name, "aliases \{other}"))
      None => existing[key] = entry.name
    }
  }
  for mapping in moves {
    for name in [mapping.source, mapping.target] {
      match filename_problem(name) {
        Some(detail) => errors.push(issue("invalid_name", name, detail))
        None => ()
      }
    }
    let src = name_key(mapping.source, policy)
    let dst = name_key(mapping.target, policy)
    if sources.contains(src) {
      errors.push(
        issue(
          "duplicate_source",
          mapping.source,
          "source mapped more than once",
        ),
      )
    }
    sources[src] = mapping.source
    match targets.get(dst) {
      Some(other) =>
        errors.push(
          issue(
            "duplicate_target",
            mapping.target,
            "also requested by \{other}",
          ),
        )
      None => targets[dst] = mapping.source
    }
    match existing.get(src) {
      None =>
        errors.push(
          issue("missing_source", mapping.source, "not present in snapshot"),
        )
      Some(actual) if actual != mapping.source =>
        errors.push(
          issue(
            "source_spelling",
            mapping.source,
            "use exact observed spelling: \{actual}",
          ),
        )
      _ => ()
    }
  }
  for mapping in moves {
    let dst = name_key(mapping.target, policy)
    if existing.contains(dst) && !sources.contains(dst) {
      errors.push(
        issue(
          "occupied_target",
          mapping.target,
          "existing entry is not being moved",
        ),
      )
    }
  }
  errors
}

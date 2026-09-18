///|
pub(all) struct NameRule {
  prefix : String
  suffix : String
  find : String
  replacement : String
  extension : String?
  sequenceStart : Int?
  sequenceWidth : Int
  onlySuffix : String?
  caseMode : String
} derive(Eq, Debug)

///|
pub fn default_rule() -> NameRule {
  {
    prefix: "",
    suffix: "",
    find: "",
    replacement: "",
    extension: None,
    sequenceStart: None,
    sequenceWidth: 3,
    onlySuffix: None,
    caseMode: "keep",
  }
}

///|
fn has_suffix(text : String, suffix : String) -> Bool {
  let t = text.iter().to_array()
  let s = suffix.iter().to_array()
  if s.length() > t.length() {
    return false
  }
  for i = 0; i < s.length(); i = i + 1 {
    if t[t.length() - s.length() + i] != s[i] {
      return false
    }
  }
  true
}

///|
fn scalar_slice(chars : Array[Char], start : Int, end : Int) -> String {
  let out = StringBuilder()
  for i = start; i < end; i = i + 1 {
    out.write_char(chars[i])
  }
  out.to_string()
}

///|
/// Literal, non-overlapping replacement; no regex or replacement interpolation.
pub fn replace_literal(
  text : String,
  needle : String,
  replacement : String,
) -> String {
  if needle.is_empty() {
    return text
  }
  let chars = text.iter().to_array()
  let pattern = needle.iter().to_array()
  let out = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    let mut matches = i + pattern.length() <= chars.length()
    if matches {
      for j = 0; j < pattern.length(); j = j + 1 {
        if chars[i + j] != pattern[j] {
          matches = false
          break
        }
      }
    }
    if matches {
      out.write_string(replacement)
      i = i + pattern.length()
    } else {
      out.write_char(chars[i])
      i = i + 1
    }
  }
  out.to_string()
}

///|
fn split_extension(name : String) -> (String, String) {
  let chars = name.iter().to_array()
  let mut dot = -1
  for i, ch in chars {
    if ch == '.' && i > 0 {
      dot = i
    }
  }
  if dot < 0 {
    (name, "")
  } else {
    (scalar_slice(chars, 0, dot), scalar_slice(chars, dot, chars.length()))
  }
}

///|
fn apply_case(text : String, mode : String) -> String {
  let out = StringBuilder()
  for ch in text.iter() {
    if mode == "lower" && ch >= 'A' && ch <= 'Z' {
      out.write_char((ch.to_int() + 32).unsafe_to_char())
    } else if mode == "upper" && ch >= 'a' && ch <= 'z' {
      out.write_char((ch.to_int() - 32).unsafe_to_char())
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// Expand rules in source-name lexical order, independent of directory listing
/// order. Sequence values apply only to selected names. Planning must follow.
pub fn generate_mappings(
  entries : Array[Entry],
  rule : NameRule,
) -> Array[Rename] raise PlanningError {
  if entries.length() > 1000 {
    raise Invalid("at most 1000 entries")
  }
  if !["keep", "lower", "upper"].contains(rule.caseMode) {
    raise Invalid("caseMode must be keep, lower or upper")
  }
  if rule.sequenceWidth < 1 || rule.sequenceWidth > 8 {
    raise Invalid("sequenceWidth must be 1..8")
  }
  match rule.sequenceStart {
    Some(n) if n < 0 || n > 1000000 =>
      raise Invalid("sequenceStart must be 0..1000000")
    _ => ()
  }
  for value in [rule.prefix, rule.suffix, rule.find, rule.replacement] {
    if value.length() > 512 {
      raise Invalid("rule text too long")
    }
  }
  for value in [rule.extension, rule.onlySuffix] {
    match value {
      Some(text) if text.length() > 512 => raise Invalid("rule option too long")
      _ => ()
    }
  }
  let result : Array[Rename] = []
  let mut serial = rule.sequenceStart.unwrap_or(0)
  for entry in sorted_entries(entries) {
    match rule.onlySuffix {
      Some(suffix) if !has_suffix(entry.name, suffix) => continue
      _ => ()
    }
    let (stem, old_ext) = split_extension(entry.name)
    let extension = match rule.extension {
      None => old_ext
      Some("") => ""
      Some(ext) => "." + ext
    }
    let transformed = replace_literal(stem, rule.find, rule.replacement)
    let numbering = match rule.sequenceStart {
      None => ""
      Some(_) => {
        let digits = serial.to_string()
        let padding = StringBuilder()
        for i = digits.length(); i < rule.sequenceWidth; i = i + 1 {
          padding.write_char('0')
        }
        padding.write_string(digits)
        serial = serial + 1
        padding.to_string()
      }
    }
    let target = apply_case(
      rule.prefix + numbering + transformed + rule.suffix + extension,
      rule.caseMode,
    )
    result.push({ source: entry.name, target, })
  }
  result
}

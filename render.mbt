///|
fn md_text(text : String) -> String {
  let out = StringBuilder()
  for c in text.iter() {
    if ['\\', '`', '|', '<', '>'].contains(c) {
      out.write_char('\\')
    }
    if c == '\r' || c == '\n' {
      out.write_char(' ')
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// Human-reviewable report without shell commands or executable script output.
pub fn render_markdown(plan : Plan) -> String {
  let out = StringBuilder()
  out.write_string("# MoonRename Plan\n\n")
  if !plan.problems.is_empty() {
    out.write_string(
      "Status: blocked. No operation sequence was generated.\n\n",
    )
    for problem in plan.problems {
      out.write_string(
        "- " +
        md_text(problem.code) +
        ": " +
        md_text(problem.name) +
        " — " +
        md_text(problem.detail) +
        "\n",
      )
    }
    return out.to_string()
  }
  out.write_string(
    "Status: ready for review. This report does not modify files.\n\n",
  )
  out.write_string(
    "Steps: \{plan.steps.length()}; temporary names: \{plan.temporaryNames.length()}; unchanged mappings: \{plan.skipped}.\n\n",
  )
  out.write_string(
    "| Step | Source | Target | Reason |\n| --- | --- | --- | --- |\n",
  )
  for step in plan.steps {
    out.write_string(
      "| \{step.index} | " +
      md_text(step.source) +
      " | " +
      md_text(step.target) +
      " | " +
      step.reason +
      " |\n",
    )
  }
  out.write_string(
    "\nEach step requires an unchanged source identity and an absent target.\n",
  )
  out.write_string(
    "Recovery assumes successful operations form a prefix. No fsync, crash atomicity, OS filename equivalence or concurrent filesystem guarantees are implied.\n",
  )
  out.to_string()
}

///|
fn dot_text(text : String) -> String {
  let out = StringBuilder()
  for c in text.iter() {
    if c == '"' || c == '\\' {
      out.write_char('\\')
    }
    if c == '\n' || c == '\r' {
      out.write_string("\\n")
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// DOT export uses opaque node IDs so filenames never become DOT syntax.
pub fn render_dot(plan : Plan) -> String {
  let out = StringBuilder()
  out.write_string("digraph rename_plan {\n  rankdir=LR;\n")
  let nodes : Map[String, Int] = Map([])
  for step in plan.steps {
    for name in [step.source, step.target] {
      if !nodes.contains(name) {
        let id = nodes.length()
        nodes[name] = id
        out.write_string("  n\{id} [label=\"" + dot_text(name) + "\"];\n")
      }
    }
    out.write_string(
      "  n\{nodes[step.source]} -> n\{nodes[step.target]} [label=\"\{step.index}: \{step.reason}\"];\n",
    )
  }
  out.write_string("}\n")
  out.to_string()
}

///|
test "literal replacement is Unicode-aware nonoverlapping and not regex" {
  assert_eq(replace_literal("aaaa", "aa", "b"), "bb")
  assert_eq(replace_literal("中😀中", "中", "新"), "新😀新")
  assert_eq(replace_literal("a.*b", ".*", "$1"), "a$1b")
  assert_eq(replace_literal("abc", "", "x"), "abc")
}

///|
test "sequence rule is deterministic and applies only to selected suffix" {
  let entries : Array[Entry] = [
    { name: "b.JPG", identity: "B", },
    { name: "ignore.txt", identity: "T", },
    { name: "a.JPG", identity: "A", },
  ]
  let rule = {
    ..default_rule(),
    prefix: "photo-",
    sequenceStart: Some(7),
    onlySuffix: Some(".JPG"),
    caseMode: "lower",
  }
  let mappings = generate_mappings(entries, rule)
  assert_eq(mappings, [
    { source: "a.JPG", target: "photo-007a.jpg", },
    { source: "b.JPG", target: "photo-008b.jpg", },
  ])
}

///|
test "extension and suffix handling preserves dotfiles" {
  let entries : Array[Entry] = [
    { name: ".hidden", identity: "1", },
    { name: "archive.tar.gz", identity: "2", },
  ]
  let rules = { ..default_rule(), suffix: "-new", extension: Some("txt"), }
  assert_eq(generate_mappings(entries, rules).map(fn(m) { m.target }), [
    ".hidden-new.txt", "archive.tar-new.txt",
  ])
}

///|
test "bad rule limits fail before expansion" {
  for
    rule in [
      { ..default_rule(), sequenceWidth: 0, },
      { ..default_rule(), sequenceStart: Some(-1), },
      { ..default_rule(), caseMode: "title", },
    ] {
    let rejected = try {
      ignore(generate_mappings([], rule))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "rule collisions are detected by same planner" {
  let entries : Array[Entry] = [
    { name: "A.txt", identity: "1", },
    { name: "a.txt", identity: "2", },
  ]
  let mappings = generate_mappings(entries, {
    ..default_rule(),
    caseMode: "lower",
  })
  assert_true(
    build_plan(entries, mappings, Exact).problems.any(fn(p) {
      p.code == "duplicate_target"
    }),
  )
}

///|
test "JSON adapter validates unknown keys and types" {
  for
    input in [
      "{}", "[]", "bad", "{\"entries\":[],\"mappings\":[],\"unexpected\":true}",
      "{\"entries\":[],\"mappings\":[],\"verify\":1}", "{\"entries\":[],\"mappings\":[],\"completed\":-1}",
      "{\"entries\":[],\"mappings\":[],\"policy\":\"windows\"}",
    ] {
    match @json.parse(plan_json(input)) {
      { "status": "error", .. } => ()
      other => fail(other.stringify())
    }
  }
}

///|
test "JSON blocked request does not contain executable steps" {
  let input =
    #|{"entries":[{"name":"a","identity":"1"},{"name":"b","identity":"2"}],"mappings":[{"source":"a","target":"b"}]}
  match @json.parse(plan_json(input)) {
    { "status": "blocked", "steps": [], .. } => ()
    other => fail(other.stringify())
  }
}

///|
test "JSON supports prefix and exhaustive boundary output" {
  let input =
    #|{"entries":[{"name":"a","identity":"1"}],"mappings":[{"source":"a","target":"b"}],"completed":1,"verify":true}
  match @json.parse(plan_json(input)) {
    {
      "status": "ready",
      "simulation": { "completed": 1, .. },
      "boundaries": Array(a),
      ..
    } => assert_eq(a.length(), 2)
    other => fail(other.stringify())
  }
}

///|
test "JSON rejects entries with empty identity or unsafe path" {
  for
    input in [
      "{\"entries\":[{\"name\":\"a\",\"identity\":\"\"}],\"mappings\":[]}", "{\"entries\":[{\"name\":\"../a\",\"identity\":\"x\"}],\"mappings\":[]}",
    ] {
    match @json.parse(plan_json(input)) {
      { "status": "blocked", .. } => ()
      other => fail(other.stringify())
    }
  }
}

///|
test "JSON recovery uses original request and exact observed snapshot" {
  let request =
    #|{"entries":[{"name":"a","identity":"1"}],"mappings":[{"source":"a","target":"b"}]}
  match
    @json.parse(recover_json(request, "[{\"name\":\"b\",\"identity\":\"1\"}]")) {
    { "status": "complete", "matchingPrefixes": [1], .. } => ()
    other => fail(other.stringify())
  }
  match
    @json.parse(
      recover_json(request, "[{\"name\":\"b\",\"identity\":\"changed\"}]"),
    ) {
    { "status": "diverged", .. } => ()
    other => fail(other.stringify())
  }
}

///|
test "rules and mappings are mutually exclusive" {
  match
    @json.parse(rules_json("{\"entries\":[],\"mappings\":[],\"rule\":{}}")) {
    { "status": "error", .. } => ()
    other => fail(other.stringify())
  }
}

///|
test "trusted checkpoint resolves equal identity ambiguity only at matching state" {
  let plan = build_plan(
    [{ name: "a", identity: "same", }, { name: "b", identity: "same", }],
    [{ source: "a", target: "b", }, { source: "b", target: "a", }],
    Exact,
  )
  assert_eq(recover_from_checkpoint(plan, plan.initial, 3).status, "complete")
  assert_eq(recover_from_checkpoint(plan, plan.initial, 1).status, "diverged")
}

///|
test "public plan audit detects altered desired state and invalid indices" {
  let plan = swapped()
  assert_true(audit_plan(plan).valid)
  assert_false(audit_plan({ ..plan, desired: [], }).valid)
  let steps = plan.steps.copy()
  steps[0] = { ..steps[0], index: 9, }
  assert_false(audit_plan({ ..plan, steps, }).valid)
}

///|
test "rendered reports expose order but not shell commands" {
  let plan = swapped()
  assert_true(render_markdown(plan).contains("temporary names: 1"))
  assert_true(render_dot(plan).contains("digraph rename_plan"))
  assert_true(render_dot(plan).contains("park"))
}

///|
test "large chain stays deterministic and restores all identities" {
  let entries : Array[Entry] = []
  let mappings : Array[Rename] = []
  for n = 0; n < 250; n = n + 1 {
    entries.push({ name: "file-\{n}", identity: "id-\{n}", })
    mappings.push({ source: "file-\{n}", target: "file-\{n + 1}", })
  }
  let plan = build_plan(entries, mappings, Exact)
  assert_eq(plan.steps.length(), 250)
  assert_eq(plan.temporaryNames.length(), 0)
  assert_eq(replay(plan.initial, plan.steps, Exact), plan.desired)
  let sim = simulate(plan, 127)
  assert_eq(replay(sim.snapshot, sim.rollback, Exact), plan.initial)
}

///|
test "source order is lexical rather than length-first" {
  let entries : Array[Entry] = [
    { name: "z", identity: "1", },
    { name: "aa", identity: "2", },
  ]
  let mappings = generate_mappings(entries, {
    ..default_rule(),
    sequenceStart: Some(1),
  })
  assert_eq(mappings[0].source, "aa")
  assert_eq(mappings[0].target, "001aa")
}

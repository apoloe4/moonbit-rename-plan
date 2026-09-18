///|
fn sample_entries() -> Array[Entry] {
  [
    { name: "a.txt", identity: "A", },
    { name: "b.txt", identity: "B", },
    { name: "c.txt", identity: "C", },
  ]
}

///|
fn swapped() -> Plan {
  build_plan(
    sample_entries(),
    [
      { source: "a.txt", target: "b.txt", },
      { source: "b.txt", target: "a.txt", },
    ],
    Exact,
  )
}

///|
test "portable names reject paths controls device names and empty names" {
  for
    name in [
      "", ".", "..", "a/b", "a\\b", "C:x", "a\n", "NUL.txt", "Com1", "trail.", "trail ",
    ] {
    assert_true(filename_problem(name) != None)
  }
  for name in ["中文.txt", "emoji😀.jpg", ".hidden", "COM10.txt", "a b"] {
    assert_eq(filename_problem(name), None)
  }
}

///|
test "ASCII folding leaves non ASCII characters intact" {
  assert_eq(name_key("AbC-Ä-中", AsciiFold), "abc-Ä-中")
  assert_eq(name_key("AbC", Exact), "AbC")
}

///|
test "preflight aggregates duplicate and missing sources" {
  let errors = validate_request(
    sample_entries(),
    [{ source: "missing", target: "x", }, { source: "missing", target: "y", }],
    Exact,
  )
  assert_true(errors.any(fn(e) { e.code == "missing_source" }))
  assert_true(errors.any(fn(e) { e.code == "duplicate_source" }))
}

///|
test "stationary targets block all operations" {
  let plan = build_plan(
    sample_entries(),
    [{ source: "a.txt", target: "c.txt", }],
    Exact,
  )
  assert_eq(plan.problems[0].code, "occupied_target")
  assert_eq(plan.steps.length(), 0)
}

///|
test "case aliases in snapshot are rejected" {
  let entries : Array[Entry] = [
    { name: "A", identity: "1", },
    { name: "a", identity: "2", },
  ]
  assert_eq(
    validate_request(entries, [], AsciiFold)[0].code,
    "snapshot_collision",
  )
  assert_eq(validate_request(entries, [], Exact).length(), 0)
}

///|
test "source spelling must match snapshot even under folding" {
  let errors = validate_request(
    [{ name: "A", identity: "1", }],
    [{ source: "a", target: "B", }],
    AsciiFold,
  )
  assert_eq(errors[0].code, "source_spelling")
}

///|
test "multiple sources cannot claim one folded target" {
  let errors = validate_request(
    sample_entries(),
    [{ source: "a.txt", target: "x", }, { source: "b.txt", target: "X", }],
    AsciiFold,
  )
  assert_true(errors.any(fn(e) { e.code == "duplicate_target" }))
}

///|
test "chain executes from free sink without temporary name" {
  let plan = build_plan(
    sample_entries(),
    [
      { source: "a.txt", target: "b.txt", },
      { source: "b.txt", target: "d.txt", },
    ],
    Exact,
  )
  assert_eq(plan.steps.length(), 2)
  assert_eq(plan.steps[0].source, "b.txt")
  assert_eq(plan.steps[1].source, "a.txt")
  assert_eq(plan.temporaryNames, [])
  assert_eq(replay(plan.initial, plan.steps, Exact), plan.desired)
}

///|
test "swap uses one parking slot and three operations" {
  let plan = swapped()
  assert_eq(plan.steps.length(), 3)
  assert_eq(plan.temporaryNames.length(), 1)
  assert_eq(plan.steps.map(fn(s) { s.reason }), ["park", "direct", "release"])
  assert_eq(replay(plan.initial, plan.steps, Exact), plan.desired)
}

///|
test "three node cycle produces four guarded renames" {
  let plan = build_plan(
    sample_entries(),
    [
      { source: "a.txt", target: "b.txt", },
      { source: "b.txt", target: "c.txt", },
      { source: "c.txt", target: "a.txt", },
    ],
    Exact,
  )
  assert_eq(plan.steps.length(), 4)
  assert_eq(plan.temporaryNames.length(), 1)
  assert_eq(replay(plan.initial, plan.steps, Exact), plan.desired)
}

///|
test "case-only rename stages through temporary name" {
  let plan = build_plan(
    [{ name: "Photo.JPG", identity: "image", }],
    [{ source: "Photo.JPG", target: "photo.jpg", }],
    AsciiFold,
  )
  assert_eq(plan.steps.length(), 2)
  assert_eq(replay(plan.initial, plan.steps, AsciiFold)[0].name, "photo.jpg")
  assert_eq(
    dependency_components(
      [{ source: "Photo.JPG", target: "photo.jpg", }],
      AsciiFold,
    )[0].kind,
    "case-only",
  )
}

///|
test "temporary names avoid initial names and requested final names" {
  let entries = sample_entries()
  entries.push({ name: ".moonrename-tmp-1", identity: "reserved", })
  let plan = build_plan(
    entries,
    [
      { source: "a.txt", target: "b.txt", },
      { source: "b.txt", target: "a.txt", },
      { source: "c.txt", target: ".moonrename-tmp-2", },
    ],
    Exact,
  )
  assert_eq(plan.temporaryNames, [".moonrename-tmp-3"])
  assert_eq(replay(plan.initial, plan.steps, Exact), plan.desired)
}

///|
test "no-op mappings are counted without steps" {
  let plan = build_plan(
    sample_entries(),
    [{ source: "a.txt", target: "a.txt", }],
    Exact,
  )
  assert_eq(plan.skipped, 1)
  assert_eq(plan.steps, [])
  assert_eq(plan.initial, plan.desired)
}

///|
test "planning independent of input enumeration order" {
  let a = swapped()
  let entries = sample_entries()
  entries.sort_by(fn(a, b) { b.name.lexical_compare(a.name) })
  let b = build_plan(
    entries,
    [
      { source: "b.txt", target: "a.txt", },
      { source: "a.txt", target: "b.txt", },
    ],
    Exact,
  )
  assert_eq(a.steps, b.steps)
  assert_eq(a.initial, b.initial)
}

///|
test "component decomposition separates chain and cycle" {
  let parts = dependency_components(
    [
      { source: "a", target: "b", },
      { source: "b", target: "a", },
      { source: "x", target: "y", },
      { source: "y", target: "z", },
    ],
    Exact,
  )
  assert_eq(parts.length(), 2)
  assert_eq(parts[0].kind, "cycle")
  assert_eq(parts[1].kind, "chain")
  assert_eq(parts[1].sources, ["x", "y"])
}

///|
test "every swap boundary can resume and roll back" {
  let plan = swapped()
  for n = 0; n <= plan.steps.length(); n = n + 1 {
    let sim = simulate(plan, n)
    assert_eq(replay(sim.snapshot, sim.remaining, Exact), plan.desired)
    assert_eq(replay(sim.snapshot, sim.rollback, Exact), plan.initial)
    let recovery = recover(plan, sim.snapshot)
    assert_eq(recovery.matchingPrefixes, [n])
  }
}

///|
test "identical identities report ambiguity rather than guessing" {
  let plan = build_plan(
    [{ name: "a", identity: "same", }, { name: "b", identity: "same", }],
    [{ source: "a", target: "b", }, { source: "b", target: "a", }],
    Exact,
  )
  let result = recover(plan, plan.initial)
  assert_eq(result.status, "ambiguous")
  assert_eq(result.matchingPrefixes, [0, 3])
  assert_eq(result.continueSteps, [])
  assert_eq(result.rollback, [])
}

///|
test "changed identity or added file refuses recovery" {
  let plan = swapped()
  let changed = sample_entries()
  changed[0] = { name: "a.txt", identity: "tampered", }
  let result = recover(plan, changed)
  assert_eq(result.status, "diverged")
  assert_true(result.differences.any(fn(d) { d.kind == "identity_changed" }))
  assert_eq(result.continueSteps, [])
  let added = sample_entries()
  added.push({ name: "new", identity: "N", })
  assert_eq(recover(plan, added).status, "diverged")
}

///|
test "missing file refuses recovery" {
  let plan = swapped()
  let result = recover(plan, [{ name: "a.txt", identity: "A", }])
  assert_eq(result.status, "diverged")
  assert_true(result.differences.any(fn(d) { d.kind == "missing" }))
}

///|
test "replay rejects overwrite stale identity and missing source" {
  let entries = sample_entries()
  for
    step in [
      {
        index: 0,
        source: "a.txt",
        target: "b.txt",
        identity: "A",
        reason: "test",
      },
      {
        index: 0,
        source: "a.txt",
        target: "new",
        identity: "wrong",
        reason: "test",
      },
      {
        index: 0,
        source: "missing",
        target: "new",
        identity: "A",
        reason: "test",
      },
    ] {
    let rejected = try {
      ignore(replay(entries, [step], Exact))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "invalid completion boundaries are rejected" {
  for n in [-1, 4] {
    let rejected = try {
      ignore(simulate(swapped(), n))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "exhaustive boundary verification reports conservation" {
  let checks = verify_boundaries(swapped())
  assert_eq(checks.length(), 4)
  assert_true(checks.all(fn(check) { check.forwardOk && check.rollbackOk }))
}

///|
test "generated permutations preserve every entry at every boundary" {
  // All 24 permutations of four files, including disjoint cycles and fixed points.
  let names = ["a", "b", "c", "d"]
  let entries = names.map(fn(name) { { name, identity: "id-" + name, } })
  let mut count = 0
  for a = 0; a < 4; a = a + 1 {
    for b = 0; b < 4; b = b + 1 {
      for c = 0; c < 4; c = c + 1 {
        for d = 0; d < 4; d = d + 1 {
          if a == b || a == c || a == d || b == c || b == d || c == d {
            continue
          }
          let destinations = [a, b, c, d]
          let mappings : Array[Rename] = []
          for i = 0; i < 4; i = i + 1 {
            mappings.push({ source: names[i], target: names[destinations[i]], })
          }
          let plan = build_plan(entries, mappings, Exact)
          assert_eq(plan.problems, [])
          for check in verify_boundaries(plan) {
            assert_true(check.forwardOk && check.rollbackOk)
          }
          for n = 0; n <= plan.steps.length(); n = n + 1 {
            assert_eq(
              recover(plan, simulate(plan, n).snapshot).matchingPrefixes,
              [n],
            )
          }
          count = count + 1
        }
      }
    }
  }
  assert_eq(count, 24)
}

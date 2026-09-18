///|
fn main {
  let entries : Array[@planner.Entry] = [
    { name: "left.txt", identity: "sha256-left", },
    { name: "right.txt", identity: "sha256-right", },
  ]
  let mappings : Array[@planner.Rename] = [
    { source: "left.txt", target: "right.txt", },
    { source: "right.txt", target: "left.txt", },
  ]
  let plan = @planner.build_plan(entries, mappings, @planner.Exact)
  println(@planner.render_markdown(plan))
  try {
    let interrupted = @planner.simulate(plan, 1)
    let recovery = @planner.recover(plan, interrupted.snapshot)
    println(ToJson::to_json(recovery).stringify())
  } catch {
    @planner.Invalid(message) => println("error: " + message)
  }
}

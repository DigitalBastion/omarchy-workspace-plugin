const assert = require("assert")
const { buildViews, fuzzyScore } = require("../WorkspaceModel.js")

const projects = [
  { id: "Acme/Backend", group: "Acme", project: "Backend", launchPath: "/projects/acme/backend", opens: "src" },
  { id: "Acme/Frontend", group: "Acme", project: "Frontend", launchPath: "/projects/acme/frontend", opens: "" },
  { id: "Other/API", group: "Other", project: "API", launchPath: "/projects/other/api", opens: "" },
]

const history = {
  entries: {
    "Acme/Backend": { count: 2, lastLaunchSeq: 3, dismissed: { recent: 3 } },
    "Acme/Frontend": { count: 1, lastLaunchSeq: 2 },
  },
}

const initial = buildViews(projects, history, "")
assert.deepStrictEqual(initial.recent.map(item => item.id), ["Acme/Frontend"])
assert.deepStrictEqual(initial.mostUsed.map(item => item.id), ["Acme/Backend"])
assert.strictEqual(initial.recent[0].deletable, true)
assert.deepStrictEqual(initial.allProjects.map(item => item.id), ["Other/API"])

const partitioned = buildViews(
  ["A", "B", "C", "D", "E", "F", "G", "H"].map(id => ({ id, group: "Group", project: id, launchPath: "/" + id })),
  { entries: {
    A: { count: 8, lastLaunchSeq: 8 }, B: { count: 7, lastLaunchSeq: 7 }, C: { count: 6, lastLaunchSeq: 6 },
    D: { count: 5, lastLaunchSeq: 5 }, E: { count: 4, lastLaunchSeq: 4 }, F: { count: 3, lastLaunchSeq: 3 },
    G: { count: 2, lastLaunchSeq: 2 }, H: { count: 1, lastLaunchSeq: 1 },
  } },
  ""
)
assert.deepStrictEqual(partitioned.recent.map(item => item.id), ["A", "B", "C"])
assert.deepStrictEqual(partitioned.mostUsed.map(item => item.id), ["D", "E", "F", "G", "H"])
assert.strictEqual(new Set(partitioned.recent.concat(partitioned.mostUsed, partitioned.allProjects).map(item => item.id)).size, 8)

const filtered = buildViews(projects, history, "ac be")
assert.deepStrictEqual(filtered.searchResults.map(item => item.id), ["Acme/Backend"])
assert.strictEqual(filtered.shownCount, 1)
assert.strictEqual(filtered.hiddenCount, 2)
assert.ok(fuzzyScore(projects[0], "ac be") >= 0)
assert.strictEqual(fuzzyScore(projects[2], "ac be"), -1)

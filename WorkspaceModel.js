function normalized(value) {
  return String(value || "").toLocaleLowerCase()
}

function projectRow(project, section) {
  return {
    id: project.id,
    group: project.group,
    project: project.project,
    opens: project.opens || "",
    launchPath: project.launchPath,
    historySection: section || "",
    deletable: section === "Recent" || section === "Most Used"
  }
}

function visibleInSection(entry, section) {
  var dismissed = entry && entry.dismissed ? entry.dismissed : {}
  var key = section === "Recent" ? "recent" : "mostUsed"
  return Number(entry && entry.lastLaunchSeq || 0) > Number(dismissed[key] || -1)
}

function historyRows(projects, history, section, limit, excludedIds) {
  var entries = history && history.entries ? history.entries : {}
  var excluded = excludedIds || {}
  var byId = {}
  for (var i = 0; i < projects.length; i++) byId[projects[i].id] = projects[i]
  var rows = []
  for (var id in entries) {
    var entry = entries[id]
    if (!byId[id] || excluded[id] || !visibleInSection(entry, section)) continue
    rows.push({ project: byId[id], entry: entry })
  }
  rows.sort(function(a, b) {
    if (section === "Most Used") {
      var count = Number(b.entry.count || 0) - Number(a.entry.count || 0)
      if (count) return count
    }
    var recent = Number(b.entry.lastLaunchSeq || 0) - Number(a.entry.lastLaunchSeq || 0)
    if (recent) return recent
    return String(a.project.id).localeCompare(String(b.project.id))
  })
  return rows.slice(0, limit).map(function(row) { return projectRow(row.project, section) })
}

function fuzzyScore(project, query) {
  var text = normalized(project.group + " " + project.project)
  var terms = normalized(query).trim().split(/\s+/)
  var score = 0
  for (var termIndex = 0; termIndex < terms.length; termIndex++) {
    var term = terms[termIndex]
    if (!term) continue
    var exact = text.indexOf(term)
    if (exact >= 0) {
      score += exact === 0 ? 1000 : 500 - Math.min(exact, 200)
      continue
    }
    var position = 0
    var gaps = 0
    for (var character = 0; character < term.length; character++) {
      var found = text.indexOf(term.charAt(character), position)
      if (found < 0) return -1
      gaps += found - position
      position = found + 1
    }
    score += 200 - Math.min(gaps, 180)
  }
  return score
}

function searchRows(projects, query) {
  var ranked = []
  for (var i = 0; i < projects.length; i++) {
    var score = fuzzyScore(projects[i], query)
    if (score >= 0) ranked.push({ project: projects[i], score: score })
  }
  ranked.sort(function(a, b) {
    var score = b.score - a.score
    return score || String(a.project.id).localeCompare(String(b.project.id))
  })
  return ranked.map(function(row) { return projectRow(row.project, "") })
}

function buildViews(projects, history, query) {
  var values = Array.isArray(projects) ? projects : []
  var needle = String(query || "").trim()
  if (needle) {
    var matches = searchRows(values, needle)
    return { recent: [], mostUsed: [], allProjects: [], searchResults: matches,
      shownCount: matches.length, hiddenCount: values.length - matches.length }
  }
  var recent = historyRows(values, history, "Recent", 3)
  var seen = {}
  recent.forEach(function(row) { seen[row.id] = true })
  var mostUsed = historyRows(values, history, "Most Used", 5, seen)
  mostUsed.forEach(function(row) { seen[row.id] = true })
  var otherProjects = values
    .filter(function(project) { return !seen[project.id] })
    .map(function(project) { return projectRow(project, "") })
  return {
    recent: recent,
    mostUsed: mostUsed,
    allProjects: otherProjects,
    searchResults: [], shownCount: values.length, hiddenCount: 0
  }
}

if (typeof module !== "undefined") module.exports = { buildViews: buildViews, fuzzyScore: fuzzyScore }

// Pure helpers for the numr overlay. No Qt in here: test/model.test.mjs loads
// this file in Node the same way Omarchy tests its own MenuModel.js.

function request(method, params, id) {
  var message = { jsonrpc: "2.0", method: method }
  if (params !== undefined) message.params = params
  if (id !== undefined) message.id = id
  return message
}

// One frame per keystroke: reset the server, replay the notes, then the typed
// line. The typed line therefore sees every variable the notes define and
// continues from their last result, exactly like a new line at the end of the
// document would in the numr TUI.
// ponytail: the whole notes file is replayed on every keystroke; window it to
// the last few thousand lines if someone keeps a novel in default.numr.
// The tokenize call comes last so the notes' variables are already bound when
// the typed line is tokenized. numr-cli before 0.9.2 answers it with "Method
// not found", which the overlay treats as "no highlighting".
function buildRequest(id, notesLines, expr) {
  return JSON.stringify([
    request("clear"),
    request("eval_lines", { lines: notesLines.concat([expr]) }, id),
    request("tokenize", { expr: expr }, tokensId(id))
  ]) + "\n"
}

function tokensId(id) {
  return "tokens:" + id
}

function ratesRequest() {
  return JSON.stringify(request("reload_rates", undefined, "rates")) + "\n"
}

// numr's own rule: a cache older than an hour is expired and the server
// silently falls back to built-in default rates, so a stale cache is refreshed
// when the calculator opens. A missing or unreadable cache counts as stale.
function ratesStale(cacheJson, nowSeconds) {
  try {
    var cache = JSON.parse(cacheJson || "")
    var stamp = Number(cache && cache.timestamp)
    return !(stamp > 0) || stamp > nowSeconds || nowSeconds - stamp >= 3600
  } catch (error) {
    return true
  }
}

// A response frame is one object or a batch array; only calls carry an id.
function parseResponses(line) {
  var parsed
  try {
    parsed = JSON.parse(line)
  } catch (error) {
    return []
  }
  var items = Array.isArray(parsed) ? parsed : [parsed]
  var replies = []
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    if (!item || item.id === undefined || item.id === null) continue
    replies.push(item.error ? { id: item.id, error: errorText(item.error) } : { id: item.id, result: item.result })
  }
  return replies
}

// The first call's reply, for frames that hold one call.
function parseResponse(line) {
  var replies = parseResponses(line)
  return replies.length ? replies[0] : null
}

function errorText(error) {
  var text = String((error && error.message) || "Error")
  if (error && error.data) text += ": " + String(error.data)
  return text
}

function splitLines(text) {
  var lines = String(text || "").replace(/\r\n?/g, "\n").split("\n")
  if (lines.length && lines[lines.length - 1] === "") lines.pop()
  return lines
}

function isComment(line) {
  var trimmed = line.trim()
  return trimmed.indexOf("#") === 0 || trimmed.indexOf("//") === 0
}

// The notes peek: the last `limit` non-blank lines paired with their values.
// Errors show no value; a prose note is a note, not a mistake.
function notesRows(lines, results, limit) {
  var rows = []
  for (var i = lines.length - 1; i >= 0 && rows.length < limit; i--) {
    if (!lines[i].trim()) continue
    var value = results[i]
    var shown = value && value.type !== "error" && value.type !== "empty" ? value.display : ""
    rows.unshift({ text: lines[i], result: shown, comment: isComment(lines[i]) })
  }
  return rows
}

// numr reports a half-typed line as "could not understand line"; that is not
// news while someone is still typing, so the result area stays quiet.
function showsResult(value) {
  if (!value || value.type === "empty") return false
  if (value.type === "error") return String(value.message || "") !== "could not understand line"
  return true
}

// Styled-text markup for the input line, colored per token the way numr-web
// does it; the palette is numr-web's, picked by the card's own brightness.
var TOKEN_COLORS = {
  dark: { number: "#b898f4", operator: "#f47898", keyword: "#f47898", variable: "#f4a860", unit: "#f4e878",
          currency: "#f4c244", "function": "#f4c244", comment: "#7d7868", punctuation: "#a8a498" },
  light: { number: "#6b4fd3", operator: "#c2185b", keyword: "#c2185b", variable: "#b35c0a", unit: "#8a6d00",
           currency: "#946a00", "function": "#946a00", comment: "#8a857a", punctuation: "#6e6a5e" }
}

function escapeMarkup(text) {
  return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/ /g, "&nbsp;")
}

function highlightMarkup(tokens, lightCard) {
  var colors = TOKEN_COLORS[lightCard ? "light" : "dark"]
  var out = ""
  for (var i = 0; i < tokens.length; i++) {
    var token = tokens[i]
    var text = escapeMarkup(token.text)
    var color = colors[token.token_type]
    out += color ? '<font color="' + color + '">' + text + "</font>" : text
  }
  return out
}

function resultText(value) {
  if (!value) return ""
  if (value.type === "error") return value.message || value.display || "Error"
  return value.display || ""
}

// Enter copies what is on screen; Ctrl+C copies the bare number for pasting
// into a spreadsheet or a form field.
function copyText(value, bare) {
  if (!value || value.type === "error" || value.type === "empty") return ""
  if (bare && value.value !== undefined && value.value !== null && value.value !== "") return String(value.value)
  return String(value.display || "")
}

// Same document the numr TUI opens: ~/.config/numr/default.numr unless
// config.toml points [files] default_path elsewhere.
// ponytail: regex instead of a TOML parser; default_path is the only key read.
function notesPath(configToml, numrDir, home) {
  var match = /^\s*default_path\s*=\s*"([^"]*)"/m.exec(String(configToml || ""))
  var path = match ? match[1] : ""
  if (!path) return numrDir + "/default.numr"
  if (path === "~" || path.indexOf("~/") === 0) path = home + path.slice(1)
  return path
}

function fileLabel(path) {
  var parts = String(path || "").split("/")
  return parts[parts.length - 1] || String(path || "")
}

function parsePayload(json) {
  try {
    var payload = JSON.parse(json || "{}")
    return payload && typeof payload === "object" && !Array.isArray(payload) ? payload : {}
  } catch (error) {
    return {}
  }
}

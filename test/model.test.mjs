import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const source = readFileSync(new URL("../NumrModel.js", import.meta.url), "utf8")
const M = new Function(source + "\nreturn { ratesStale, showsResult, buildRequest, tokensId, ratesRequest, parseResponse, parseResponses, splitLines, notesRows, resultText, copyText, notesPath, fileLabel, parsePayload, highlightMarkup }")()

test("buildRequest clears, then replays notes plus the typed line under one id", () => {
  const frame = M.buildRequest(7, ["rent = $1200", "rent * 12"], "+ 10%")
  assert.ok(frame.endsWith("\n"))
  const batch = JSON.parse(frame)
  assert.deepEqual(batch[0], { jsonrpc: "2.0", method: "clear" })
  assert.deepEqual(batch[1], { jsonrpc: "2.0", method: "eval_lines", params: { lines: ["rent = $1200", "rent * 12", "+ 10%"] }, id: 7 })
  assert.deepEqual(batch[2], { jsonrpc: "2.0", method: "tokenize", params: { expr: "+ 10%" }, id: M.tokensId(7) })
  assert.deepEqual(JSON.parse(M.ratesRequest()), { jsonrpc: "2.0", method: "reload_rates", id: "rates" })
})

test("parseResponse finds the call inside a batch and reports protocol errors as text", () => {
  const ok = M.parseResponse('[{"jsonrpc":"2.0","result":[{"type":"number","value":"4","display":"4"}],"id":3}]')
  assert.equal(ok.id, 3)
  assert.equal(ok.result[0].display, "4")
  const bad = M.parseResponse('{"jsonrpc":"2.0","error":{"code":-32602,"message":"Invalid params","data":"missing lines"},"id":4}')
  assert.deepEqual(bad, { id: 4, error: "Invalid params: missing lines" })
  assert.equal(M.parseResponse("not json"), null)
  assert.equal(M.parseResponse('{"jsonrpc":"2.0","result":{"message":"Cleared"}}'), null)
})

test("parseResponses returns every call in a batch; an old server's tokenize error is just one of them", () => {
  const replies = M.parseResponses('[{"jsonrpc":"2.0","result":[{"type":"number","value":"4","display":"4"}],"id":3},{"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"},"id":"tokens:3"}]')
  assert.equal(replies.length, 2)
  assert.equal(replies[0].id, 3)
  assert.deepEqual(replies[1], { id: "tokens:3", error: "Method not found" })
  assert.deepEqual(M.parseResponses("not json"), [])
})

test("highlightMarkup colors known tokens, escapes markup, keeps spaces", () => {
  const tokens = [
    { text: "a", token_type: "variable" }, { text: " ", token_type: "whitespace" },
    { text: "<", token_type: "operator" }, { text: " ", token_type: "whitespace" },
    { text: "2", token_type: "number" }, { text: " x&y", token_type: "text" },
  ]
  assert.equal(M.highlightMarkup(tokens, false),
    '<font color="#f4a860">a</font>&nbsp;<font color="#f47898">&lt;</font>&nbsp;<font color="#b898f4">2</font>&nbsp;x&amp;y')
  assert.equal(M.highlightMarkup([{ text: "5", token_type: "number" }], true), '<font color="#6b4fd3">5</font>')
})

test("splitLines drops only the trailing newline", () => {
  assert.deepEqual(M.splitLines("a\nb\n"), ["a", "b"])
  assert.deepEqual(M.splitLines("a\r\n\r\nb"), ["a", "", "b"])
  assert.deepEqual(M.splitLines(""), [])
})

test("notesRows keeps the last non-blank lines, hides errors, flags comments", () => {
  const lines = ["# budget", "rent = $1200", "", "oops words", "rent * 12", ""]
  const results = [
    { type: "empty", display: "" },
    { type: "currency", display: "$1200.00", value: "1200.00" },
    { type: "empty", display: "" },
    { type: "error", display: "Error: could not understand line", message: "could not understand line" },
    { type: "currency", display: "$14400.00", value: "14400.00" },
    { type: "empty", display: "" }
  ]
  assert.deepEqual(M.notesRows(lines, results, 3), [
    { text: "rent = $1200", result: "$1200.00", comment: false },
    { text: "oops words", result: "", comment: false },
    { text: "rent * 12", result: "$14400.00", comment: false }
  ])
  assert.deepEqual(M.notesRows(lines, results, 9)[0], { text: "# budget", result: "", comment: true })
})

test("showsResult hides half-typed lines but keeps real errors", () => {
  assert.equal(M.showsResult(null), false)
  assert.equal(M.showsResult({ type: "empty", display: "" }), false)
  assert.equal(M.showsResult({ type: "error", message: "could not understand line", display: "Error: could not understand line" }), false)
  assert.equal(M.showsResult({ type: "error", message: "division by zero", display: "Error: division by zero" }), true)
  assert.equal(M.showsResult({ type: "number", value: "4", display: "4" }), true)
})

test("resultText and copyText follow the value type", () => {
  const hex = { type: "number", value: "22", display: "0x16" }
  const err = { type: "error", display: "Error: division by zero", message: "division by zero" }
  assert.equal(M.resultText(hex), "0x16")
  assert.equal(M.resultText(err), "division by zero")
  assert.equal(M.resultText(null), "")
  assert.equal(M.copyText(hex, false), "0x16")
  assert.equal(M.copyText(hex, true), "22")
  assert.equal(M.copyText(err, false), "")
  assert.equal(M.copyText({ type: "empty", display: "" }, true), "")
})

test("notesPath honours numr's default_path and falls back to default.numr", () => {
  assert.equal(M.notesPath("", "/home/fs/.config/numr", "/home/fs"), "/home/fs/.config/numr/default.numr")
  assert.equal(M.notesPath('[files]\ndefault_path = "~/Documents/money.numr"\n', "/x", "/home/fs"), "/home/fs/Documents/money.numr")
  assert.equal(M.notesPath('default_path = "/srv/notes.numr"', "/x", "/home/fs"), "/srv/notes.numr")
  assert.equal(M.fileLabel("/home/fs/.config/numr/default.numr"), "default.numr")
})

test("ratesStale follows numr's one-hour cache rule", () => {
  const now = 1_800_000_000
  assert.equal(M.ratesStale(JSON.stringify({ timestamp: now - 10, rates: {} }), now), false)
  assert.equal(M.ratesStale(JSON.stringify({ timestamp: now - 3600, rates: {} }), now), true)
  assert.equal(M.ratesStale(JSON.stringify({ timestamp: now + 60, rates: {} }), now), true)
  assert.equal(M.ratesStale("", now), true)
  assert.equal(M.ratesStale("{not json", now), true)
})

test("parsePayload tolerates garbage", () => {
  assert.deepEqual(M.parsePayload('{"expr":"2+2"}'), { expr: "2+2" })
  assert.deepEqual(M.parsePayload(""), {})
  assert.deepEqual(M.parsePayload("[1]"), {})
  assert.deepEqual(M.parsePayload("{nope"), {})
})

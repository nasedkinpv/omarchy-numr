import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "NumrModel.js" as Model

// Spotlight-style numr calculator. One long-lived `numr-cli --server` answers
// every keystroke. The notes file is the document the numr TUI opens, so a
// line kept here shows up there, and variables defined there work here.
Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: (root.manifest && root.manifest.id) || "io.github.nasedkinpv.numr"

  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || (root.home + "/.config")
  property string numrConfig: ""
  readonly property string notesFile: Model.notesPath(root.numrConfig, root.configDir + "/numr", root.home)
  readonly property int notesLimit: 6

  property bool opened: false
  property string expr: ""
  property var result: null
  property var notesLines: []
  property var notesRows: []
  property int requestId: 0
  property var inflight: null
  property string pending: ""
  property bool serverStarted: false
  property bool serverBroken: false
  property string status: ""
  property bool caretOn: true
  property string ratesCache: ""
  property real lastRatesAttempt: 0
  property bool ratesManual: false

  // Shares the [menu] surface tokens, like the emoji and clipboard overlays,
  // so a theme that styles the menu styles this card too.
  readonly property color background: Commons.Color.menu.background
  readonly property color foreground: Commons.Color.menu.text
  readonly property color accent: Commons.Color.menu.selectedText
  readonly property color border: Commons.Color.menu.border
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", root.border, Math.max(1, Style.space(2)))
  readonly property color scrim: Commons.Color.menu.scrim
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int cardWidth: Math.min(Style.space(620), panel.width - Style.gapsOut * 2)
  readonly property int resultLineHeight: Math.round(Style.font.displayLarge * 1.25)
  readonly property bool hasResult: Model.showsResult(root.result)
  readonly property bool resultIsError: root.hasResult && root.result.type === "error"

  function open(payloadJson) {
    var payload = Model.parsePayload(payloadJson)
    root.opened = true
    root.status = ""
    root.serverBroken = false
    if (typeof payload.expr === "string") root.expr = payload.expr
    root.caretOn = true
    notesView.reload()
    root.ensureServer()
    root.refreshRatesIfStale()
    root.evaluate()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    root.expr = ""
    root.result = null
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function setExpr(text) {
    root.expr = text
    root.caretOn = true
    root.evaluate()
  }

  function setNotes(text) {
    root.notesLines = Model.splitLines(text)
    if (root.opened) root.evaluate()
  }

  function evaluate() {
    evalTimer.restart()
  }

  function sendEval() {
    root.requestId += 1
    root.inflight = { id: root.requestId, lines: root.notesLines, expr: root.expr }
    root.send(Model.buildRequest(root.requestId, root.notesLines, root.expr))
  }

  function send(frame) {
    if (server.running && root.serverStarted) {
      server.write(frame)
      return
    }
    root.pending = frame
    root.ensureServer()
  }

  function ensureServer() {
    if (server.running || root.serverBroken) return
    server.running = true
  }

  function handleResponse(data) {
    var reply = Model.parseResponse(data)
    if (!reply || !root.inflight || reply.id !== root.inflight.id) return
    var sent = root.inflight
    if (reply.error) {
      root.result = { type: "error", display: reply.error, message: reply.error }
      return
    }
    var values = Array.isArray(reply.result) ? reply.result : []
    var count = sent.lines.length
    root.notesRows = Model.notesRows(sent.lines, values.slice(0, count), root.notesLimit)
    root.result = sent.expr.trim() ? (values[count] || null) : null
  }

  function copyResult(bare, andClose) {
    var text = Model.copyText(root.result, bare)
    if (!text) {
      root.flash("Nothing to copy yet")
      return
    }
    Quickshell.execDetached(["wl-copy", "--", text])
    if (andClose) root.dismiss()
    else root.flash("Copied " + text)
  }

  function paste() {
    var clip = String(Quickshell.clipboardText || "").split("\n")[0]
    if (clip) root.setExpr(root.expr + clip)
  }

  // Appends the typed line to the notes file as-is. A plain shell append keeps
  // the write atomic enough for a line and creates ~/.config/numr on a machine
  // where numr has never run; the FileView watcher picks the change up.
  function appendToNotes() {
    if (!root.expr.trim() || appendProc.running) return
    appendProc.command = ["sh", "-c", 'mkdir -p -- "$(dirname -- "$1")" && printf "%s\\n" "$2" >> "$1"', "numr-notes", root.notesFile, root.expr]
    appendProc.running = true
    root.setExpr("")
  }

  function openNotes() {
    Util.execArgv(["omarchy-launch-or-focus-tui", "numr", root.notesFile])
    root.dismiss()
  }

  // Rates are fetched by a separate short-lived numr-cli so the live server
  // keeps answering keystrokes while the network call runs. numr persists the
  // result to its cache; the live server reads that cache only at startup, and
  // since every keystroke replays the full state anyway, restarting it is free.
  function reloadRates() {
    root.ratesManual = true
    root.flash("Updating rates…")
    root.startRatesRefresh()
  }

  function refreshRatesIfStale() {
    var now = Date.now() / 1000
    if (!Model.ratesStale(root.ratesCache, now)) return
    if (now - root.lastRatesAttempt < 600) return
    root.startRatesRefresh()
  }

  function startRatesRefresh() {
    if (ratesProc.running) return
    root.lastRatesAttempt = Date.now() / 1000
    ratesProc.running = true
  }

  function ratesDone(output) {
    var reply = Model.parseResponse(output)
    var ok = !!reply && !reply.error
    if (root.ratesManual) root.flash(ok ? "Rates updated" : "Rates: " + (reply ? reply.error : "numr-cli failed"))
    root.ratesManual = false
    if (!ok) return
    server.running = false
    root.evaluate()
  }

  function flash(message) {
    root.status = message
    statusTimer.restart()
  }

  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    if (event.key === Qt.Key_Escape) {
      if (root.expr) root.setExpr("")
      else root.dismiss()
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (shift) root.appendToNotes()
      else root.copyResult(false, true)
    } else if (ctrl && event.key === Qt.Key_O) {
      root.openNotes()
    } else if (ctrl && event.key === Qt.Key_R) {
      root.reloadRates()
    } else if (ctrl && (event.key === Qt.Key_C || event.key === Qt.Key_Insert)) {
      root.copyResult(true, false)
    } else if ((ctrl && event.key === Qt.Key_V) || (shift && event.key === Qt.Key_Insert)) {
      root.paste()
    } else if (Util.editsFilter(event, root.expr)) {
      root.setExpr(Util.editedFilter(event, root.expr))
    } else if (!ctrl && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
      root.setExpr(root.expr + event.text)
    } else {
      return
    }
    event.accepted = true
  }

  Timer {
    id: evalTimer
    interval: 30
    repeat: false
    onTriggered: root.sendEval()
  }

  Timer {
    id: statusTimer
    interval: 2500
    repeat: false
    onTriggered: root.status = ""
  }

  Timer {
    interval: 530
    running: root.opened
    repeat: true
    onTriggered: root.caretOn = !root.caretOn
  }

  FileView {
    id: configView
    path: root.configDir + "/numr/config.toml"
    printErrors: false
    onLoaded: root.numrConfig = text()
    onLoadFailed: root.numrConfig = ""
  }

  FileView {
    id: ratesView
    path: root.configDir + "/numr/rates.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.ratesCache = text()
    onLoadFailed: root.ratesCache = ""
    onFileChanged: reload()
  }

  FileView {
    id: notesView
    path: root.notesFile
    watchChanges: true
    printErrors: false
    onLoaded: root.setNotes(text())
    onLoadFailed: root.setNotes("")
    onFileChanged: reload()
  }

  Process {
    id: server
    command: ["numr-cli", "--server"]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(data) { root.handleResponse(data) }
    }
    onStarted: {
      root.serverStarted = true
      if (root.pending) {
        server.write(root.pending)
        root.pending = ""
      }
    }
    onRunningChanged: {
      if (server.running) return
      // Never reached onStarted: the binary is missing. Exited later: a crash
      // or a stale process, which the next keystroke restarts.
      if (!root.serverStarted) root.serverBroken = true
      root.serverStarted = false
    }
  }

  Process {
    id: ratesProc
    command: ["sh", "-c", 'printf "%s\\n" "$1" | numr-cli --server', "numr-rates", Model.ratesRequest().trim()]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ratesDone(text)
    }
  }

  Process {
    id: appendProc
    onExited: function(exitCode) {
      root.flash(exitCode === 0 ? "Kept in " + Model.fileLabel(root.notesFile) : "Could not write " + root.notesFile)
      notesView.reload()
    }
  }

  // A plain layer-shell window, as the emoji and clipboard overlays build
  // theirs: works on every Quattro release, including ones without the
  // newer OverlayWindow helper.
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "numr"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: content.implicitHeight + card.contentTopInset + card.contentBottomInset + Style.spacing.xs
      radius: Style.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.round(parent.height * 0.26)
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { root.handleKey(event) }
      }

      Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.spacing.sm

        // The input line: just the text and a caret, no chrome.
        Item {
          width: parent.width
          height: inputText.implicitHeight

          Text {
            id: inputText
            textFormat: Text.PlainText
            text: root.expr || "Calculate…"
            opacity: root.expr ? 1 : 0.45
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            width: parent.width - caret.width - Style.space(4)
            elide: Text.ElideLeft
          }

          Rectangle {
            id: caret
            width: Math.max(1, Style.space(2))
            height: inputText.font.pixelSize
            x: root.expr ? Math.min(inputText.contentWidth, inputText.width) + Style.space(2) : 0
            anchors.verticalCenter: parent.verticalCenter
            color: root.accent
            visible: root.caretOn
          }
        }

        // The answer, right-aligned and large. Keeps its line while typing so
        // the card does not jump between results.
        Item {
          width: parent.width
          height: root.expr ? root.resultLineHeight : hintText.implicitHeight

          Text {
            id: resultText
            visible: root.hasResult
            textFormat: Text.PlainText
            text: Model.resultText(root.result)
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            color: root.resultIsError ? root.foreground : root.accent
            opacity: root.resultIsError ? 0.5 : 1
            font.family: root.fontFamily
            font.pixelSize: root.resultIsError ? Style.font.subtitle : Style.font.displayLarge
            font.bold: !root.resultIsError
          }

          Text {
            id: hintText
            visible: !root.expr
            textFormat: Text.PlainText
            text: root.serverBroken
              ? "numr-cli is not available. Install numr (AUR: numr-bin) and reopen."
              : "20% of 150  ·  5 km in miles  ·  $100 in eur  ·  2 h + 30 min"
            width: parent.width
            elide: Text.ElideRight
            color: root.serverBroken ? Commons.Color.urgent : root.foreground
            opacity: root.serverBroken ? 0.9 : 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // The last lines of the notes document with their values.
        Column {
          width: parent.width
          spacing: Style.spacing.xs
          visible: root.notesRows.length > 0

          Rectangle {
            width: parent.width
            height: 1
            color: root.border
            opacity: 0.25
          }

          Item {
            width: parent.width
            height: notesHeader.implicitHeight + Style.spacing.xs

            Text {
              id: notesHeader
              textFormat: Text.PlainText
              text: "Notes"
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              color: root.foreground
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              textFormat: Text.PlainText
              text: Model.fileLabel(root.notesFile) + " · " + root.notesLines.length + (root.notesLines.length === 1 ? " line" : " lines")
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              color: root.foreground
              opacity: 0.35
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Repeater {
            model: root.notesRows

            delegate: Item {
              id: noteRow
              required property var modelData
              width: parent.width
              height: Math.max(noteText.implicitHeight, noteValue.implicitHeight) + Style.spacing.xs

              Text {
                id: noteText
                textFormat: Text.PlainText
                text: noteRow.modelData.text
                anchors.left: parent.left
                anchors.right: noteValue.left
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                color: root.foreground
                opacity: noteRow.modelData.comment ? 0.45 : 0.85
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: noteValue
                textFormat: Text.PlainText
                text: noteRow.modelData.result
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: root.accent
                opacity: 0.9
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setExpr(noteRow.modelData.text)
              }
            }
          }
        }

        // One quiet line of guidance, replaced by a short status after an action.
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.status || "Enter copy  ·  Shift+Enter keep as note  ·  Ctrl+O notes  ·  Esc"
          elide: Text.ElideRight
          color: root.status ? root.accent : root.foreground
          opacity: root.status ? 0.95 : 0.35
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}

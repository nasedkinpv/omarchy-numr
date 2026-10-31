import QtQuick
import qs.Ui

// One glyph in the bar; the calculator itself is the overlay entry point.
BarWidget {
  id: root
  moduleName: "io.github.nasedkinpv.numr"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰃬"
    tooltipText: "numr calculator"
    onPressed: function(pressedButton) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle io.github.nasedkinpv.numr '{}'")
    }
  }
}

import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// UniFi in the bar. The button shows the gateway glyph (and, toggled with a
// right click, the live download rate). The panel shows WAN rates, the busiest
// clients, and one switch per policy route ("traffic route"), which is how
// UniFi sends a device through a VPN client.
//
// All network work happens in bin/omarchy-unifi, which prints JSON:
//   bar    -> {text, tooltip, class, down, up, clients, ...}   (bar refresh)
//   panel  -> {bar, routes[], clients[], client_count}        (panel open)
//   vpn <route-id> on|off                                     (switches)
Panel {
  id: root
  moduleName: "tolixx.unifi"
  ipcTarget: "tolixx.unifi"
  manageIpc: false

  readonly property string helper: String(Qt.resolvedUrl("bin/omarchy-unifi")).replace(/^[a-z]+:\/\//, "")
  readonly property int refreshSec: Math.max(5, Number(setting("refreshIntervalSec", 10)) || 10)
  readonly property bool showRate: setting("showRate", false) === true

  property var barInfo: ({})
  property var routes: []
  property var clients: []
  property int clientCount: 0
  property string error: ""
  property string busyRoute: ""
  property int routeIndex: 0
  property bool cursorActive: false

  readonly property string glyph: "󰑩"
  // A widget instance can exist without a bar (e.g. while the shell reloads), so fall back to theme values.
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFam: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property bool wanOk: barInfo.class === "ok"

  function rate(bytesPerSec) {
    var bits = (Number(bytesPerSec) || 0) * 8
    var units = ["bit/s", "kbit/s", "Mbit/s", "Gbit/s"]
    var i = 0
    while (bits >= 1000 && i < units.length - 1) { bits /= 1000; i++ }
    return (i === 0 ? Math.round(bits) : bits.toFixed(1)) + " " + units[i]
  }

  function shortRate(bytesPerSec) {
    var bits = (Number(bytesPerSec) || 0) * 8
    if (bits >= 1e9) return (bits / 1e9).toFixed(1) + "G"
    if (bits >= 1e6) return (bits / 1e6).toFixed(1) + "M"
    if (bits >= 1e3) return Math.round(bits / 1e3) + "k"
    return Math.round(bits) + ""
  }

  function parse(text) {
    try { return JSON.parse(String(text || "").trim() || "{}") } catch (e) { return { error: "bad output from omarchy-unifi" } }
  }

  function refreshBar() {
    if (root.opened || barProc.running) return
    barProc.running = true
  }

  function refreshPanel() {
    if (panelProc.running) return
    panelProc.running = true
  }

  function setRoute(route, on) {
    if (!route || vpnProc.running) return
    root.busyRoute = route.id
    vpnProc.command = [root.helper, "vpn", route.id, on ? "on" : "off"]
    vpnProc.running = true
  }

  function toggleSelectedRoute() {
    if (routeIndex < 0 || routeIndex >= routes.length) return
    var r = routes[routeIndex]
    setRoute(r, !r.enabled)
  }

  function toggleRate() {
    root.settings = Object.assign({}, root.settings, { showRate: !root.showRate })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  IpcHandler {
    target: "tolixx.unifi"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function toggleRate() { root.toggleRate() }
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      refreshPanel()
    }
  }

  Component.onCompleted: refreshBar()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: barProc
    command: [root.helper, "bar"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d = root.parse(text)
        root.barInfo = d
        root.error = d.class === "error" ? (d.tooltip || "UniFi unreachable") : ""
      }
    }
  }

  Process {
    id: panelProc
    command: [root.helper, "panel"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d = root.parse(text)
        if (d.error) { root.error = d.error; return }
        root.error = ""
        root.barInfo = d.bar || {}
        root.routes = d.routes || []
        root.clients = d.clients || []
        root.clientCount = d.client_count || 0
        if (root.routeIndex >= root.routes.length) root.routeIndex = 0
      }
    }
  }

  Process {
    id: vpnProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d = root.parse(text)
        if (d.error) root.error = d.error
      }
    }
    onExited: {
      root.busyRoute = ""
      root.refreshPanel()
    }
  }

  Timer { interval: root.refreshSec * 1000; running: !root.opened; repeat: true; onTriggered: root.refreshBar() }
  Timer { interval: 3000; running: root.opened; repeat: true; onTriggered: root.refreshPanel() }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showRate && !vertical ? root.shortRate(root.barInfo.down) + " " + root.glyph : root.glyph
    slotSize: Style.bar.iconSlot * (root.showRate && !vertical ? 2.6 : 1)
    opacity: root.error !== "" ? 0.5 : 1
    tooltipText: root.error !== "" ? root.error : (root.barInfo.text || "")
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleRate()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.routes.length === 0) return
        if (!root.cursorActive) { root.cursorActive = true; return }
        var d = dy !== 0 ? dy : dx
        root.routeIndex = (root.routeIndex + d + root.routes.length) % root.routes.length
      }
      onActivateRequested: if (root.cursorActive) root.toggleSelectedRoute()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: glyph · gateway · download ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.glyph
            color: root.fg
            font.family: root.fontFam
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "UniFi"
              color: root.fg
              font.family: root.fontFam
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: (root.error !== ""
                ? root.error
                : [root.barInfo.isp || "WAN", root.wanOk ? "online" : (root.barInfo.status || "…"), root.clientCount + " clients"].join(" · ")).toUpperCase()
              color: Qt.darker(root.fg, 1.4)
              font.family: root.fontFam
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(20)
          visible: root.error === ""

          Column {
            width: (parent.width - parent.spacing) / 2
            InfoPair { label: "Download"; value: root.rate(root.barInfo.down) }
          }
          Column {
            width: (parent.width - parent.spacing) / 2
            InfoPair { label: "Upload"; value: root.rate(root.barInfo.up) }
          }
        }

        // ---------- VPN routes ----------
        PanelSeparator { foreground: root.fg; visible: root.routes.length > 0 }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.routes.length > 0

          PanelSectionHeader {
            text: "VPN ROUTES"
            foreground: root.fg
            fontFamily: root.fontFam
          }

          Repeater {
            model: root.routes
            Item {
              required property var modelData
              required property int index
              width: parent.width
              implicitHeight: Math.max(routeLabels.implicitHeight, routeSwitch.implicitHeight) + Style.space(6)

              Column {
                id: routeLabels
                anchors.left: parent.left
                anchors.right: routeSwitch.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  textFormat: Text.PlainText
                  text: modelData.name || "Route " + (index + 1)
                  color: root.fg
                  font.family: root.fontFam
                  font.pixelSize: Style.font.bodySmall
                  font.bold: root.cursorActive && root.routeIndex === index
                  elide: Text.ElideRight
                  width: parent.width
                }
                Text {
                  textFormat: Text.PlainText
                  text: "via " + modelData.vpn + (modelData.online > 0 ? " · " + modelData.online + " online" : "")
                  color: root.fg
                  opacity: 0.55
                  font.family: root.fontFam
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                }
              }

              ToggleSwitch {
                id: routeSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: modelData.enabled
                busy: root.busyRoute === modelData.id
                foreground: root.fg
                hasCursor: root.cursorActive && root.routeIndex === index
                onToggled: root.setRoute(modelData, !modelData.enabled)
                onHovered: function(h) { if (h) { root.cursorActive = true; root.routeIndex = index } }
              }
            }
          }
        }

        // ---------- Busiest clients ----------
        PanelSeparator { foreground: root.fg; visible: root.clients.length > 0 }

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap
          visible: root.clients.length > 0

          PanelSectionHeader {
            text: "BUSIEST CLIENTS"
            foreground: root.fg
            fontFamily: root.fontFam
          }

          Repeater {
            model: root.clients.slice(0, 8)
            InfoPair {
              required property var modelData
              label: (modelData.wired ? "󰈀  " : "󰖩  ") + modelData.name + (modelData.route && modelData.route.enabled ? "  · " + modelData.route.vpn : "")
              value: "↓ " + root.shortRate(modelData.tx) + "  ↑ " + root.shortRate(modelData.rx)
            }
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label; width: Math.min(implicitWidth, parent.width - parent.children[2].implicitWidth - parent.spacing * 2); elide: Text.ElideRight }
    Item { width: Math.max(0, parent.width - parent.children[0].width - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.fg
    opacity: 0.6
    font.family: root.fontFam
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.fontFam
    font.pixelSize: Style.font.bodySmall
  }
}

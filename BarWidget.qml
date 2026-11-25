// Self-contained bar widget: the popup lives right here, anchored to the
// icon button via PopupCard, exactly like the original widget (this is what
// made the old widget position/size itself correctly — PopupCard anchors to
// anchorItem automatically, no manual screen-edge math needed).
//
// Data layer is rewired to the service surface confirmed working in the
// newer plugin (popupModel for live notifications, historyDir for on-disk
// history) instead of the old pendingModel/pastModel calls, which is why
// notifications weren't showing.
//
// UI: no more Pending/Recently tabs — a search field, a
// "Recent and live notifications" label with a Clear all button, then a
// single merged, newest-first list below (live + history combined).
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "NotificationLogic.js" as NotificationLogic

BarWidget {
  id: root
  moduleName: "shafayet.notifications"

  property bool popupOpen: false
  readonly property bool opened: popupOpen
  property bool unread: false
  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function markUnread() {
    if (!root.popupOpen && root.liveCount > 0) root.unread = true
  }
  function markRead() {
    if (!root.popupOpen) root.unread = false
  }

  IpcHandler {
    target: "shafayet.notifications"
    function markRead(): void { root.broadcast("markRead") }
  }

  property string query: ""
  property var filteredRows: []
  property ListModel rowsModel: ListModel {}
  property var historyRows: []

  property var _exitingKeys: ({})
  property var _animateKeys: ({})
  property Timer animateKeyExpiry: Timer {
    interval: 2000
    repeat: false
    onTriggered: root._animateKeys = ({})
  }

  function isExitingKey(key) { return root._exitingKeys[key] === true }

  // Locally-dismissed history entries, hidden until they drop out of the
  // on-disk history on their own (see dismissRow()).
  property var hiddenHistoryKeys: ({})
  function historyKey(row) {
    // Key on timestamp, never id: notification ids restart from 1 on every
    // server generation, so two distinct history entries can share an id —
    // dismissing one would carry the shared key into hiddenHistoryKeys and
    // hide both. Each persisted file is uniquely identified by its timestamp.
    return "t:" + String(row.timestamp || 0) + "|" + String(row.app || "") + "|" + String(row.summary || "")
  }

  function rowKey(row) {
    return (row.isLive ? "L" : "H") + "|" + String(row.timestamp || 0)
      + "|" + String(row.app || "") + "|" + String(row.summary || "")
  }

  // Look up the long-running notifications service through the shell host.
  readonly property var hostShell: bar && bar.shell ? bar.shell : null
  readonly property var notificationService: hostShell && hostShell.serviceFor
    ? hostShell.serviceFor("shafayet.notifications") : null

  readonly property int liveCount: notificationService && notificationService.popupModel
    ? notificationService.popupModel.count : 0
  readonly property string historyDir: notificationService && notificationService.historyDir
    ? String(notificationService.historyDir) : ""

  // ---- DND (guarded: lives on Omarchy's first-party service, not here).
  readonly property bool dndSupported: !!notificationService
    && typeof notificationService.doNotDisturb === "boolean"
    && typeof notificationService.setDoNotDisturb === "function"
  readonly property bool dndOn: dndSupported && notificationService.doNotDisturb
  function toggleDnd() {
    if (dndSupported) notificationService.setDoNotDisturb(!notificationService.doNotDisturb)
  }

  readonly property string icon: {
    if (root.dndOn) return "󰂛"
    if (root.unread) return "󱅫"
    return "󰂚"
  }

  // Theme palette. Use the popup surface roles so the center follows the
  // theme's `[popups]` colors, not just the generic foreground token.
  // The `Commons.` prefix matters: bare `Color` is Qt's built-in QML type.
  readonly property color colForeground: Commons.Color.popups.text
  readonly property color colDim: Qt.darker(colForeground, 1.4)
  readonly property color colBorder: Style.normalBorderFor(colForeground, Commons.Color.accent)
  readonly property color colSurface: Commons.Color.popups.background
  readonly property color colAccent: Commons.Color.accent
  readonly property int cardRadius: notificationService && notificationService.cornerRadius
    ? notificationService.cornerRadius : Style.cornerRadius

  function notificationIconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    return Quickshell.iconPath(value, true)
  }

  function formatTimestamp(ms) {
    var date = new Date(Number(ms) || Date.now())
    var now = new Date()
    var sameDay = date.getFullYear() === now.getFullYear()
      && date.getMonth() === now.getMonth() && date.getDate() === now.getDate()
    var time = date.toLocaleTimeString(Qt.locale(), "h:mm AP")
    return sameDay ? time : date.toLocaleDateString(Qt.locale(), "MMM d") + " · " + time
  }

  function rowMatches(row) {
    var needle = root.query.trim().toLowerCase()
    if (needle === "") return true
    var haystack = [row.app, row.summary, row.body].join(" ").toLowerCase()
    return haystack.indexOf(needle) >= 0
  }

  function rebuildRows() {
    var rows = []
    for (var h = 0; h < root.historyRows.length; ++h) {
      var history = root.historyRows[h]
      if (root.hiddenHistoryKeys[root.historyKey(history)]) continue
      if (!rowMatches(history)) continue
      rows.push({
        sourceIndex: -1,
        isLive: false,
        id: history.id,
        app: history.app,
        appIcon: history.appIcon,
        summary: history.summary,
        body: history.body,
        glyph: history.glyph,
        urgency: history.urgency,
        timestamp: history.timestamp
      })
    }
    var model = root.notificationService ? root.notificationService.popupModel : null
    if (!model) { root.syncModel(rows); return }
    for (var i = 0; i < model.count; ++i) {
      var row = model.get(i)
      if (!row || !rowMatches(row)) continue
      rows.push({
        sourceIndex: i,
        isLive: true,
        id: row.id !== undefined ? row.id : null,
        app: String(row.appName || row.app || "Unknown application"),
        appIcon: String(row.appIcon || ""),
        summary: String(row.summary || "Notification"),
        body: String(row.body || ""),
        glyph: String(row.glyph || NotificationLogic.glyphFromHints(row.hints)),
        urgency: Number(row.urgency || 1),
        timestamp: Number(row.timestamp || 0)
      })
    }
    rows.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
    root.syncModel(rows)
  }

  function syncModel(rows) {
    var model = root.rowsModel
    var i, key
    var keep = {}
    for (i = 0; i < rows.length; ++i) keep[root.rowKey(rows[i])] = true
    for (i = model.count - 1; i >= 0; --i) {
      var rowKey = model.get(i).rowKey
      if (root.isExitingKey(rowKey)) continue
      if (!keep[rowKey]) model.remove(i, 1)
    }
    var byKey = {}
    for (i = 0; i < model.count; ++i) {
      var existingKey = model.get(i).rowKey
      if (byKey[existingKey] === undefined) byKey[existingKey] = i
    }
    for (i = 0; i < rows.length; ++i) {
      key = root.rowKey(rows[i])
      var entry = {
        rowKey: key,
        isLive: rows[i].isLive,
        sourceIndex: rows[i].sourceIndex,
        id: rows[i].id,
        app: rows[i].app,
        appIcon: rows[i].appIcon,
        summary: rows[i].summary,
        body: rows[i].body,
        glyph: rows[i].glyph,
        urgency: rows[i].urgency,
        timestamp: rows[i].timestamp
      }
      if (byKey[key] === undefined) {
        model.append(entry)
        byKey[key] = model.count - 1
        root._animateKeys[key] = true
        root.animateKeyExpiry.restart()
      } else {
        var idx = byKey[key]
        var cur = model.get(idx)
        if (cur.body !== entry.body || cur.summary !== entry.summary
            || cur.app !== entry.app || cur.appIcon !== entry.appIcon
            || cur.glyph !== entry.glyph || cur.urgency !== entry.urgency
            || cur.sourceIndex !== entry.sourceIndex) {
          model.set(idx, entry)
        }
      }
    }
    var order = []
    for (i = 0; i < rows.length; ++i) order.push(root.rowKey(rows[i]))
    var target = 0
    var pos = 0
    while (pos < model.count && target < order.length) {
      var curKey = model.get(pos).rowKey
      if (root.isExitingKey(curKey)) { ++pos; continue }
      if (curKey === order[target]) { ++pos; ++target; continue }
      var src = -1
      for (i = pos + 1; i < model.count; ++i) {
        if (model.get(i).rowKey === order[target]) { src = i; break }
      }
      if (src < 0) break
      model.move(src, pos, 1)
      ++pos
      ++target
    }
    root.filteredRows = rows
  }

  function dismissRow(rowKey) {
    if (root.isExitingKey(rowKey)) return
    var found = null
    for (var i = 0; i < root.rowsModel.count; ++i) {
      var r = root.rowsModel.get(i)
      if (r.rowKey === rowKey) { found = r; break }
    }
    if (!found) return
    root._exitingKeys[rowKey] = true
    if (found.isLive) {
      if (root.notificationService && typeof root.notificationService.dismissPopup === "function")
        root.notificationService.dismissPopup(found.sourceIndex)
      root.unread = false
    } else {
      var key = root.historyKey(found)
      var next = Object.assign({}, root.hiddenHistoryKeys)
      next[key] = true
      root.hiddenHistoryKeys = next
      if (root.notificationService && typeof root.notificationService.removeHistoryEntry === "function")
        root.notificationService.removeHistoryEntry(found.id)
    }
  }

  function finishExit(rowKey) {
    delete root._exitingKeys[rowKey]
    root.rebuildRows()
  }

  function clearSearch() {
    root.query = ""
    searchField.text = ""
  }

  function clearAll() {
    if (!root.notificationService) return
    if (typeof root.notificationService.clearPopups === "function") root.notificationService.clearPopups()
    if (typeof root.notificationService.clearHistory === "function") root.notificationService.clearHistory()
    root.historyRows = []
    root.hiddenHistoryKeys = ({})
    rebuildRows()
    // With everything cleared there's nothing left to look at; close the popup.
    root.popupOpen = false
  }

  function parseHistory(raw) {
    var parsed = []
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; ++i) {
      var line = lines[i].trim()
      if (!line) continue
      try {
        var value = JSON.parse(line)
        if (!value || typeof value !== "object") continue
        parsed.push({
          id: value.id !== undefined ? value.id : (value.originalId !== undefined ? value.originalId : null),
          app: String(value.app || "Unknown application"),
          appIcon: String(value.appIcon || ""),
          summary: String(value.summary || "Notification"),
          body: String(value.body || ""),
          glyph: String(value.glyph || ""),
          urgency: Number(value.urgency === undefined ? 1 : value.urgency),
          timestamp: Number(value.timestamp || 0)
        })
      } catch (e) {
        // A torn write is ignored, matching the first-party parser.
      }
    }
    parsed.sort(function(a, b) { return b.timestamp - a.timestamp })
    root.historyRows = parsed.slice(0, root.notificationService && root.notificationService.historyLimit
      ? Number(root.notificationService.historyLimit) : 10)
    rebuildRows()
  }

  onPopupOpenChanged: {
    if (popupOpen) {
      clearSearch()
      root.rowsModel.clear()
      root._animateKeys = ({})
      root._exitingKeys = ({})
      refreshHistory()
      rebuildRows()
    } else {
      root.rowsModel.clear()
    }
  }

  // Event-driven history refresh: no polling loop. Events are (a) the shared
  // notifications service signaling a history write, (b) live rows leaving the
  // model (expire/dismiss archives them), (c) the panel opening. All coalesce
  // through short debounce timers so a notification burst costs one refresh.
  //
  // Both the acted-upon and history signals live on the service, which only
  // resolves after the bar injects itself into this widget (Bar.qml assigns
  // `bar` via Qt.callLater, i.e. after creation/onCompleted). Connections
  // re-targets reactively the instant notificationService turns non-null, so
  // these stay wired from the moment the service is available — no dependence
  // on the popup having been opened first.
  Connections {
    target: root.notificationService
    function onNotificationActedUpon() { root.unread = false }
    function onHistoryChanged() { root.queueHistoryRefresh() }
  }

  Timer {
    id: historyRefreshDebounce
    interval: 80
    repeat: false
    onTriggered: root.refreshHistory()
  }
  function queueHistoryRefresh() { historyRefreshDebounce.restart() }

  Timer {
    id: rebuildDebounce
    interval: 80
    repeat: false
    onTriggered: root.rebuildRows()
  }
  // Model signals can cascade (one in-place update touches several roles);
  // coalesce bursts into a single rebuild instead of one per changed role.
  function queueRebuild() { rebuildDebounce.restart() }

  function refreshHistory() {
    if (!root.historyDir || historyReader.running) return
    historyReader.command = ["bash", "-c",
      "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", root.historyDir]
    historyReader.running = true
  }
  onQueryChanged: rebuildRows()

  Process {
    id: historyReader
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseHistory(text)
    }
  }

  Connections {
    target: root.notificationService ? root.notificationService.popupModel : null
    function onCountChanged() { root.markUnread(); root.queueRebuild() }
    function onDataChanged() { root.queueRebuild() }
    function onRowsInserted() { root.markUnread(); root.queueRebuild() }
    function onRowsRemoved() {
      // The removal archives the row into on-disk history, so pull the fresh
      // copy after the model settles; historyChanged usually fires too, but
      // this path catches replay dismissals that never touch historyDir.
      root.queueRebuild()
      root.queueHistoryRefresh()
      // A shortcut can dismiss the last toast while the center is closed.
      // No live rows means nothing is unread, regardless of popup state.
      if (root.liveCount === 0) root.unread = false
    }
    function onModelReset() { root.queueRebuild() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: root.unread && !root.dndOn
    tooltipText: root.dndOn ? "DND on — right-click to turn off"
      : (root.liveCount > 0 ? root.liveCount + " live notifications" : "Notification Center")

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.toggleDnd()
      } else {
        if (!root.popupOpen) root.unread = false
        root.popupOpen = !root.popupOpen
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: searchField
    contentWidth: popup.fittedContentWidth(Style.space(440))
    contentHeight: popup.cappedContentHeight(Style.space(540))

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(10)

      // ----------------------------------------- header
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          text: "Notifications"
          font.family: root.bar ? root.bar.fontFamily : ""
          color: root.colForeground
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          text: root.liveCount === 1 ? "1 notification" : root.liveCount + " notifications"
          font.family: root.bar ? root.bar.fontFamily : ""
          color: root.colDim
          font.pixelSize: Style.font.caption
        }

        Item { Layout.fillWidth: true }

        Row {
          id: dndSlider
          visible: root.dndSupported
          Layout.preferredHeight: Math.max(Style.space(24), Style.font.bodySmall + Style.spacing.controlPaddingY * 2)
          spacing: Style.space(6)
          Layout.alignment: Qt.AlignVCenter

          Text {
            text: "DND"
            font.family: root.bar ? root.bar.fontFamily : ""
            color: root.dndOn ? root.colAccent : root.colDim
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }

          ToggleSwitch {
            id: dndSwitch
            checked: root.dndOn
            accent: root.colAccent
            foreground: root.colForeground
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.toggleDnd()
          }
        }

        BorderSurface {
          Layout.preferredWidth: Style.space(22)
          Layout.preferredHeight: Style.space(22)
          radius: Math.min(Style.space(6), root.cardRadius)
          color: closeHeaderArea.containsMouse ? root.colBorder : "transparent"
          borderSpec: Border.flat(root.colBorder, Style.normalBorderWidth)

          Text {
            anchors.centerIn: parent
            text: "󰅖"
            font.family: root.bar ? root.bar.fontFamily : ""
            color: root.colForeground
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: closeHeaderArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.close()
          }
        }
      }

      // ----------------------------------------- search
      TextField {
        id: searchField
        Layout.fillWidth: true
        placeholderText: "Search notifications"
        activeFocusOnPress: true
        onTextEdited: root.query = text
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.query.length > 0) {
              root.clearSearch()
            } else {
              root.close()
            }
            event.accepted = true
          }
        }
      }

      // ----------------------------------------- label + clear all
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          Layout.fillWidth: true
          text: root.query.trim() === "" ? "Recent and live notifications" : listView.count + " matching notifications"
          font.family: root.bar ? root.bar.fontFamily : ""
          color: root.colDim
          font.pixelSize: Style.font.caption
        }

        BorderSurface {
          Layout.preferredWidth: clearLabel.implicitWidth + Style.space(16)
          Layout.preferredHeight: Math.max(Style.space(22), Style.font.bodySmall + Style.spacing.controlPaddingY * 2)
          radius: Math.min(Style.space(6), root.cardRadius)
          color: clearArea.containsMouse ? root.colBorder : "transparent"
          borderSpec: Border.flat(root.colBorder, Style.normalBorderWidth)

          Text {
            id: clearLabel
            anchors.centerIn: parent
            text: "Clear all"
            font.family: root.bar ? root.bar.fontFamily : ""
            color: root.colForeground
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: clearArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clearAll()
          }
        }
      }

      // ----------------------------------------- list
      ListView {
        id: listView
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: Style.space(8)
        model: root.rowsModel
        visible: count > 0

        addDisplaced: Transition {
          NumberAnimation { properties: "x,y"; duration: 220; easing.type: Easing.OutCubic }
        }
        removeDisplaced: Transition {
          NumberAnimation { properties: "x,y"; duration: 220; easing.type: Easing.OutCubic }
        }

        delegate: BorderSurface {
          id: rowCard
          required property int index
          required property string rowKey
          required property string app
          required property string appIcon
          required property string summary
          required property string body
          required property string glyph
          required property int urgency
          required property double timestamp

          readonly property string smallIconSource: root.notificationIconSource(appIcon)
          readonly property bool hasIcon: glyph === "" && smallIconSource.length > 0
          readonly property string sanitizedBody: NotificationLogic.sanitizeBody(body, app, appIcon)

          // ---- expand on hover ----
          readonly property bool hovering: rowHoverArea.containsMouse
          property bool expandArmed: false
          readonly property bool fullBodyShown: rowCard.hovering && rowCard.expandArmed

          Timer {
            interval: 600
            running: rowCard.hovering
            onTriggered: rowCard.expandArmed = true
          }

          // ---- enter/exit animations ----
          // Behavior-driven like the shafayet.notifications toasts (delegates
          // animate themselves instead of relying on view-level transitions).
          property bool exiting: false
          property real entranceShift: 0
          property real exitShift: 0
          Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
          Behavior on entranceShift { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
          Behavior on exitShift { NumberAnimation { duration: 260; easing.type: Easing.InOutCubic } }
          transform: [
            Translate { y: rowCard.entranceShift },
            Translate { x: rowCard.exitShift }
          ]
          Timer {
            id: exitTimer
            interval: 280
            repeat: false
            onTriggered: root.finishExit(rowCard.rowKey)
          }
          Component.onCompleted: {
            var animate = root._animateKeys[rowCard.rowKey] === true
            if (animate) {
              rowCard.opacity = 0
              rowCard.entranceShift = 14
              Qt.callLater(function() {
                rowCard.opacity = 1
                rowCard.entranceShift = 0
              })
            }
          }

          width: listView.width
          implicitHeight: rowContent.implicitHeight + Style.spacing.panelGap
          radius: root.cardRadius
          color: "transparent"
          borderSpec: Border.flat(root.colBorder, Style.normalBorderWidth)

          // Left click dismisses the notification.
          MouseArea {
            id: rowHoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onExited: rowCard.expandArmed = false
            onClicked: {
              if (rowCard.exiting) return
              rowCard.exiting = true
              root.dismissRow(rowCard.rowKey)
              rowCard.opacity = 0
              rowCard.exitShift = 520
              exitTimer.start()
            }
          }

          RowLayout {
            id: rowContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: rowCard.borderLeft + Style.space(12)
            anchors.rightMargin: rowCard.borderRight + Style.space(12)
            spacing: Style.space(10)

            Text {
              Layout.alignment: Qt.AlignTop
              visible: glyph !== ""
              text: glyph
              textFormat: Text.PlainText
              color: urgency === 2 ? Commons.Color.urgent : Commons.Color.accent
              font.family: root.bar ? root.bar.fontFamily : ""
              font.pixelSize: Style.font.icon
            }

            Item {
              Layout.preferredWidth: Style.space(32)
              Layout.preferredHeight: Style.space(32)
              Layout.alignment: Qt.AlignVCenter
              visible: rowCard.hasIcon && rowIconImage.status !== Image.Error

              Image {
                id: rowIconImage
                anchors.fill: parent
                source: rowCard.smallIconSource
                fillMode: Image.PreserveAspectFit
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                asynchronous: true
                smooth: true
              }
            }

            Column {
              id: textCol
              Layout.fillWidth: true
              spacing: Style.space(2)

              RowLayout {
                id: appTimeRow
                width: textCol.width
                Text {
                  Layout.fillWidth: true
                  text: app
                  textFormat: Text.PlainText
                  font.family: root.bar ? root.bar.fontFamily : ""
                  color: root.colDim
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
                Text {
                  text: root.formatTimestamp(timestamp)
                  font.family: root.bar ? root.bar.fontFamily : ""
                  color: root.colDim
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                width: textCol.width
                visible: summary.length > 0
                text: summary
                textFormat: Text.PlainText
                font.family: root.bar ? root.bar.fontFamily : ""
                color: root.colForeground
                font.pixelSize: Style.font.subtitle
                font.bold: true
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
              }

              // Body capped at 3 lines; hovering expands to the full text. The
              // height animates (Behavior on height), so cards grow smoothly.
              Item {
                id: bodySlot
                width: textCol.width
                height: rowCard.fullBodyShown
                  ? fullBodyText.implicitHeight : cappedBodyMetric.implicitHeight
                visible: rowCard.sanitizedBody.length > 0
                clip: true
                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Text {
                  id: fullBodyText
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  text: rowCard.sanitizedBody
                  textFormat: Text.PlainText
                  font.family: root.bar ? root.bar.fontFamily : ""
                  color: root.colDim
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  elide: Text.ElideRight
                  maximumLineCount: rowCard.fullBodyShown ? -1 : 3
                }

                Text {
                  id: cappedBodyMetric
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  opacity: 0
                  text: rowCard.sanitizedBody
                  textFormat: Text.PlainText
                  font.family: root.bar ? root.bar.fontFamily : ""
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  elide: Text.ElideRight
                  maximumLineCount: 3
                }
              }
            }

          }
        }
      }

      // ----------------------------------------- empty state
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: listView.count === 0

        ColumnLayout {
          anchors.centerIn: parent
          spacing: Style.space(6)

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: "󰂚"
            font.family: root.bar ? root.bar.fontFamily : ""
            color: root.colBorder
            font.pixelSize: Style.font.displayLarge
          }

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.query.trim() === "" ? "No notifications" : "No matching notifications"
            font.family: root.bar ? root.bar.fontFamily : ""
            color: root.colDim
            font.pixelSize: Style.font.body
          }
        }
      }

      // ----------------------------------------- footer legend
      Text {
        Layout.fillWidth: true
        text: "Hover to expand · Left-click to dismiss · Esc closes"
        font.family: root.bar ? root.bar.fontFamily : ""
        color: Qt.darker(root.colForeground, 1.55)
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}

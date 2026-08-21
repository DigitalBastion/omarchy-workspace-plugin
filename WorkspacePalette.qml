import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Presentation-only project palette. Its controller supplies already-ranked
// rows and owns scanning, history, launching, and persistence.
Item {
    id: root

    // --- Controller-facing state ------------------------------------------------
    property bool opened: false
    property var activeScreen: null       // Set to Quickshell.screens' active monitor.
    property string query: ""
    property var recentItems: []          // [{ id, group, project, opens, deletable }]
    property var mostUsedItems: []        // Same row shape; only the first 5 render.
    property var allProjects: []          // Same row shape.
    property var searchResults: []        // Fuzzy-ranked, flat list supplied by controller.
    property bool loading: false          // Controller scan state; results remain usable.
    property string statusMessage: ""     // Controller-provided scan or launch feedback.
    property int hiddenCount: 0
    property int projectCount: -1         // -1 derives from allProjects.length.
    property int shownCount: -1           // Set when count differs from rendered rows.
    property string editorLabel: "VS Code"
    property bool editorToggleAvailable: false
    property string terminalLabel: "Default terminal"
    property bool dimBackdrop: false      // Reserved configuration; off by default.

    property color background: Color.menu.background
    property color foreground: Color.menu.text
    property color border: Color.menu.border
    property color selectedBackground: Color.menu.selectedBackground
    property color selectedText: Color.menu.selectedText
    property color selectedBorder: Color.menu.selectedBorder
    property color scrim: Color.menu.scrim
    property string fontFamily: Style.font.menuFamily
    property int paletteWidth: Style.space(560)
    property int maximumHeight: Style.space(620)

    readonly property bool searching: query.trim().length > 0
    readonly property int effectiveShownCount: shownCount >= 0 ? shownCount : displayModel.count
    readonly property int effectiveProjectCount: projectCount >= 0 ? projectCount : allProjects.length
    readonly property var currentItem: selectedIndex >= 0 && selectedIndex < displayModel.count ? displayModel.get(selectedIndex) : null
    property int selectedIndex: 0

    // The controller performs side effects in response to these signals.
    signal queryEdited(string query)
    signal launchRequested(var project)
    signal editRequested(var project)
    signal editorCycleRequested
    signal terminalRequested(var project)
    signal refreshRequested
    signal deleteRequested(var project)
    signal dismissed

    function open() {
        opened = true;
        selectedIndex = 0;
        rebuild();
        Qt.callLater(function () {
            searchInput.forceActiveFocus();
        });
    }

    function close() {
        if (!opened)
            return;
        opened = false;
        dismissed();
    }

    function setQuery(value) {
        query = String(value || "");
    }

    // Convenience entry point for controllers that receive all lists together.
    function setProjectData(recent, mostUsed, projects, rankedResults) {
        recentItems = recent || [];
        mostUsedItems = mostUsed || [];
        allProjects = projects || [];
        searchResults = rankedResults || [];
    }

    function rebuild() {
        var previousId = currentItem ? String(currentItem.id || "") : "";
        displayModel.clear();

        function appendRows(rows, section, limit) {
            var source = rows || [];
            var count = limit > 0 ? Math.min(source.length, limit) : source.length;
            for (var i = 0; i < count; i++) {
                var item = source[i] || ({});
                displayModel.append({
                    id: String(item.id || (item.group || "") + "/" + (item.project || "")),
                    group: String(item.group || ""),
                    project: String(item.project || item.label || "Untitled project"),
                    opens: String(item.opens || item.source || ""),
                    deletable: item.deletable === true,
                    section: section,
                    payload: item
                });
            }
        }

        if (searching) {
            appendRows(searchResults, "", 0);
        } else {
            appendRows(recentItems, "Recent", 3);
            appendRows(mostUsedItems, "Most Used", 5);
            appendRows(allProjects, "Other Projects", 0);
        }

        selectedIndex = 0;
        if (previousId) {
            for (var j = 0; j < displayModel.count; j++) {
                if (displayModel.get(j).id === previousId) {
                    selectedIndex = j;
                    break;
                }
            }
        }
        Qt.callLater(revealSelected);
    }

    function moveSelection(delta) {
        if (displayModel.count === 0)
            return;
        selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count;
        revealSelected();
    }

    function revealSelected() {
        if (selectedIndex >= 0 && selectedIndex < displayModel.count)
            projectList.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function activate(index) {
        if (index < 0 || index >= displayModel.count)
            return;
        selectedIndex = index;
        launchRequested(displayModel.get(index).payload);
    }

    function clearOrClose() {
        if (query.length > 0)
            setQuery("");
        else
            close();
    }

    onQueryChanged: {
        if (searchInput.text !== query)
            searchInput.text = query;
        selectedIndex = 0;
        rebuild();
    }
    onRecentItemsChanged: rebuild()
    onMostUsedItemsChanged: rebuild()
    onAllProjectsChanged: rebuild()
    onSearchResultsChanged: rebuild()

    ListModel {
        id: displayModel
    }

    PanelWindow {
        id: panel
        visible: root.opened
        screen: root.activeScreen
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-quattro-menu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            visible: root.dimBackdrop
            color: root.scrim
        }

        // This sits below the palette, so it only receives clicks outside it.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        BorderSurface {
            id: palette
            width: Math.min(root.paletteWidth, panel.width - Style.gapsOut * 2)
            height: Math.min(implicitHeight, Math.min(root.maximumHeight, panel.height - Style.gapsOut * 2))
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            color: root.background
            radius: Style.cornerRadius
            borderSpec: Border.surfaceSpec("menu", "border", root.border, Math.max(1, Style.space(1)))
            padding: Style.spacing.panelPadding

            implicitHeight: content.implicitHeight + contentTopInset + contentBottomInset

            // Consume clicks on unused card space so they cannot reach the dismiss area.
            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: content
                anchors.fill: parent
                anchors.topMargin: palette.contentTopInset
                anchors.bottomMargin: palette.contentBottomInset
                anchors.leftMargin: palette.contentLeftInset
                anchors.rightMargin: palette.contentRightInset
                spacing: Style.spacing.lg

                Item {
                    id: searchArea
                    width: parent.width
                    height: searchInput.implicitHeight

                    TextField {
                        id: searchInput
                        anchors.fill: parent
                        foreground: root.foreground
                        accent: Color.accent
                        placeholderText: "Find a project…"
                        font.family: root.fontFamily
                        // Keep typed text clear of the editor indicator.
                        rightPadding: editorBadge.width + Style.spacing.controlPaddingX + Style.spacing.xs
                        Accessible.name: "Find a project"
                        onTextEdited: {
                            root.query = text;
                            root.queryEdited(text);
                        }
                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: function (event) {
                            if (event.key === Qt.Key_Up) {
                                root.moveSelection(-1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down) {
                                root.moveSelection(1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.activate(root.selectedIndex);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.clearOrClose();
                                event.accepted = true;
                            } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_E) {
                                root.editorCycleRequested();
                                event.accepted = true;
                            } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_T) {
                                if (root.currentItem)
                                    root.terminalRequested(root.currentItem.payload);
                                event.accepted = true;
                            } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_R) {
                                root.refreshRequested();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Delete && root.currentItem && root.currentItem.deletable) {
                                root.deleteRequested(root.currentItem.payload);
                                event.accepted = true;
                            }
                        }
                    }

                    Rectangle {
                        id: editorBadge
                        anchors.right: searchInput.right
                        anchors.rightMargin: Style.spacing.controlPaddingX
                        anchors.verticalCenter: searchInput.verticalCenter
                        width: Math.min(implicitWidth, searchInput.width * 0.52)
                        height: Math.min(searchInput.height - Style.spacing.xs, implicitHeight)
                        implicitWidth: editorBadgeLabel.implicitWidth + Style.spacing.controlPaddingX * 2
                        implicitHeight: editorBadgeLabel.implicitHeight + Style.spacing.xxs * 2
                        radius: Style.cornerRadius
                        color: root.selectedBackground
                        border.color: root.selectedBorder
                        border.width: Math.max(1, Style.space(1))
                        Accessible.name: root.editorToggleAvailable ? "Active editor: " + root.editorLabel + ". Press Control E to change editor." : "Active editor: " + root.editorLabel

                        Text {
                            id: editorBadgeLabel
                            anchors.fill: parent
                            anchors.leftMargin: Style.spacing.controlPaddingX
                            anchors.rightMargin: Style.spacing.controlPaddingX
                            text: root.editorLabel + (root.editorToggleAvailable ? " · Ctrl+E" : "")
                            color: root.selectedText
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Item {
                    id: feedback
                    width: parent.width
                    visible: root.loading || root.statusMessage.trim().length > 0
                    height: visible ? feedbackContent.implicitHeight : 0

                    Column {
                        id: feedbackContent
                        width: parent.width
                        spacing: Style.spacing.xxs

                        Text {
                            visible: root.loading
                            width: parent.width
                            text: "Scanning projects…"
                            color: Color.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.weight: Font.Medium
                        }

                        Text {
                            visible: root.statusMessage.trim().length > 0
                            width: parent.width
                            text: root.statusMessage
                            color: Color.urgent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.weight: Font.Medium
                            wrapMode: Text.Wrap
                        }
                    }
                }

                Item {
                    width: parent.width
                    // Bound against the screen, not palette.height: the palette's
                    // implicit height is itself derived from this list.
                    height: Math.max(Style.space(64), Math.min(projectList.contentHeight, Math.max(Style.space(64), panel.height - Style.gapsOut * 2 - searchInput.height - footer.implicitHeight - Style.spacing.lg * 2 - feedback.height - (feedback.visible ? Style.spacing.lg : 0) - palette.contentTopInset - palette.contentBottomInset)))

                    ListView {
                        id: projectList
                        anchors.fill: parent
                        clip: true
                        model: displayModel
                        spacing: Style.spacing.xxs
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }
                        section.property: "section"
                        section.criteria: ViewSection.FullString
                        section.delegate: Text {
                            required property string section
                            width: projectList.width
                            height: section.length ? Style.space(18) : 0
                            visible: section.length > 0
                            text: section
                            color: root.foreground
                            opacity: 0.58
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.weight: Font.DemiBold
                            verticalAlignment: Text.AlignVCenter
                        }

                        delegate: Component {
                            BorderSurface {
                                id: row
                                required property int index
                                required property string group
                                required property string project
                                required property string opens
                                required property bool deletable
                                required property var payload
                                width: projectList.width
                                height: Style.space(30)
                                radius: Style.cornerRadius
                                readonly property bool current: root.selectedIndex === index
                                color: current ? root.selectedBackground : "transparent"
                                borderSpec: current ? Border.surfaceSpec("menu", "selected-border", root.selectedBorder, 0) : Border.none()

                                Item {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Style.spacing.md
                                    anchors.rightMargin: Style.spacing.md

                                    Text {
                                        id: projectLabel
                                        anchors.left: parent.left
                                        anchors.right: opensLabel.visible ? opensLabel.left : parent.right
                                        anchors.rightMargin: opensLabel.visible ? Style.spacing.xs : 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: row.group.length > 0 ? row.group + " / " + row.project : row.project
                                        color: row.current ? root.selectedText : root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.bodySmall
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        id: opensLabel
                                        visible: row.opens.length > 0
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, parent.width * 0.42)
                                        text: "opens: " + row.opens
                                        color: row.current ? root.selectedText : root.foreground
                                        opacity: 0.54
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.selectedIndex = row.index
                                    onClicked: root.activate(row.index)
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: displayModel.count === 0
                            text: root.searching ? "No matching projects" : "No projects yet"
                            color: root.foreground
                            opacity: 0.56
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                        }
                    }
                }

                Column {
                    id: footer
                    width: parent.width
                    Item {
                        width: parent.width
                        height: Math.max(shortcuts.implicitHeight, projectCounter.implicitHeight)

                        Text {
                            id: shortcuts
                            anchors.left: parent.left
                            anchors.right: projectCounter.left
                            anchors.rightMargin: Style.spacing.md
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Enter open" + (root.editorToggleAvailable ? " · Ctrl+E editor" : "") + " · Ctrl+T terminal · Ctrl+R refresh" + (root.currentItem && root.currentItem.deletable ? " · Del remove" : "")
                            color: root.foreground
                            opacity: 0.46
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.Wrap
                            Accessible.name: text
                        }

                        Text {
                            id: projectCounter
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.effectiveShownCount + "/" + root.effectiveProjectCount
                            color: root.foreground
                            opacity: 0.56
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            Accessible.name: root.effectiveShownCount + " of " + root.effectiveProjectCount + " projects shown"
                        }
                    }
                }
            }
        }
    }
}

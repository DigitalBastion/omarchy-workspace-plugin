import Quickshell.Io
import QtQuick
import "WorkspaceModel.js" as Model

Item {
    id: root

    // Injected by Omarchy's menu host.
    property var shell: null
    property var manifest: null
    property bool opened: false
    property var projects: []
    property var history: ({
            entries: {},
            sequence: 0
        })
    property string editor: "code"
    property string terminalName: "Default terminal"
    property int snapshotSerial: 0
    property var pendingRequests: []
    property var pendingLaunch: null
    property bool launcherStarted: false
    readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("bin/workspace-opener-store")).replace("file://", ""))

    function open(_payloadJson) {
        opened = true;
        palette.statusMessage = "";
        palette.setQuery("");
        palette.open();
        refresh();
        enqueue("terminal-name", {});
    }

    function close() {
        palette.close();
    }

    function refresh() {
        snapshotSerial += 1;
        palette.loading = true;
        enqueue("snapshot", {
            serial: snapshotSerial
        });
    }

    function enqueue(action, request) {
        pendingRequests = pendingRequests.concat([
            {
                action: action,
                request: request
            }
        ]);
        startNextRequest();
    }

    function startNextRequest() {
        if (helperProc.running || pendingRequests.length === 0)
            return;
        var next = pendingRequests[0];
        pendingRequests = pendingRequests.slice(1);
        helperProc.action = next.action;
        helperProc.request = next.request;
        helperProc.reply = "";
        helperProc.started = false;
        helperProc.command = [helperPath, next.action];
        helperProc.running = true;
    }

    function applySnapshot(response, serial) {
        if (serial !== snapshotSerial)
            return;
        palette.loading = false;
        if (response.error) {
            palette.statusMessage = response.error;
            return;
        }
        projects = Array.isArray(response.projects) ? response.projects : [];
        history = response.history || ({
                entries: {},
                sequence: 0
            });
        editor = response.preferences && response.preferences.editor === "cursor" ? "cursor" : "code";
        palette.dimBackdrop = response.preferences && response.preferences.dimBackdrop === true;
        palette.statusMessage = "";
        render();
    }

    function applyHistory(response) {
        if (response.error) {
            palette.statusMessage = response.error;
            return;
        }
        history = response.history || history;
        render();
    }

    function handleHelperReply(action, request, text, exitCode) {
        var response;
        try {
            response = JSON.parse(text || "{}");
        } catch (e) {
            response = {
                error: "Workspace helper returned invalid data"
            };
        }
        if (exitCode !== 0 && !response.error)
            response.error = "Workspace helper failed";
        if (action === "snapshot")
            applySnapshot(response, request.serial);
        else if (action === "history")
            applyHistory(response);
        else if (action === "terminal-name" && !response.error) {
            terminalName = String(response.name || "Default terminal");
            palette.terminalLabel = terminalName;
        }
    }

    function render() {
        var views = Model.buildViews(projects, history, palette.query);
        palette.projectCount = projects.length;
        palette.shownCount = views.shownCount;
        palette.hiddenCount = views.hiddenCount;
        palette.editorLabel = editor === "cursor" ? "Cursor" : "VS Code";
        palette.setProjectData(views.recent, views.mostUsed, views.allProjects, views.searchResults);
    }

    function cycleEditor() {
        editor = editor === "code" ? "cursor" : "code";
        render();
    }

    function launch(project, terminal) {
        if (!project || !project.launchPath)
            return;
        pendingLaunch = project;
        launcherStarted = false;
        launcherProc.command = terminal ? ["xdg-terminal-exec", "--dir=" + String(project.launchPath)] : ["uwsm", "app", "--", editor === "cursor" ? "cursor" : "code", "--new-window", String(project.launchPath)];
        palette.close();
        launcherProc.running = true;
    }

    function recordLaunch(project) {
        enqueue("history", {
            action: "record",
            id: String(project.id || "")
        });
    }

    WorkspacePalette {
        id: palette
        activeScreen: root.shell && root.shell.screens ? root.shell.screens.active : null
        terminalLabel: root.terminalName
        onQueryEdited: function (_query) {
            root.render();
        }
        onLaunchRequested: function (project) {
            root.launch(project, false);
        }
        onEditorCycleRequested: root.cycleEditor()
        onTerminalRequested: function (project) {
            root.launch(project, true);
        }
        onRefreshRequested: root.refresh()
        onDeleteRequested: function (project) {
            root.enqueue("history", {
                action: "dismiss",
                id: String(project.id || ""),
                section: String(project.historySection || "")
            });
        }
        onDismissed: root.opened = false
    }

    Process {
        id: helperProc
        property string action: ""
        property var request: ({})
        property string reply: ""
        property bool started: false
        stdinEnabled: true
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: helperProc.reply = text || ""
        }
        onStarted: {
            started = true;
            write(JSON.stringify(request) + "\n");
        }
        onRunningChanged: {
            if (!running && !started && action) {
                root.handleHelperReply(action, request, JSON.stringify({
                    error: "Workspace helper could not start"
                }), 1);
                Qt.callLater(root.startNextRequest);
            }
        }
        onExited: function (exitCode, _exitStatus) {
            root.handleHelperReply(action, request, reply, exitCode);
            Qt.callLater(root.startNextRequest);
        }
    }

    Process {
        id: launcherProc
        onRunningChanged: {
            if (!running && !root.launcherStarted && root.pendingLaunch) {
                palette.statusMessage = "Could not start the selected application";
                root.opened = true;
                palette.open();
                root.pendingLaunch = null;
            }
        }
        onStarted: {
            root.launcherStarted = true;
            root.recordLaunch(root.pendingLaunch);
        }
        onExited: function (exitCode, _exitStatus) {
            root.pendingLaunch = null;
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.System
import qs.Services.UI
import qs.Services.UI
import qs.Widgets

Item {
    id: root
    property var launcher: null

    property string name: "plugins.bitwarden"

    property bool locked: true

    property var entries: []

    property string entryId: ""
    property string passwd: ""

    function handleCommand(query) {
        return query.startsWith(">rbw");
    }

    function open() {
        if(launcher) {
            launcher.setSearchText(">rbw ");
            launcher.open();
        }
    }

    function lock() {
        lockProcess.running = true;
    }

    function unlock() {
        unlockProcess.running = true;
    }

    Process {
        id: checkUnlockedProcess
        running: false
        command: ["rbw", "unlocked"]

        onExited: function (exitCode, _) {
            root.locked = exitCode !== 0;
            Logger.i("RBW", "Locked: " + root.locked);
            if (!root.locked) {
                entriesProcess.running = true;
            }
        }
    }

    Process {
        id: unlockProcess
        running: false
        command: ["rbw", "unlock"]

        onExited: function (exitCode, _exitStatus) {
            root.locked = exitCode !== 0;
            Logger.i("RBW", "Locked: " + root.locked);
            if (!root.locked) {
                root.open();
            }
        }
    }

    Process {
        id: lockProcess
        running: false
        command: ["rbw", "lock"]

        onExited: function (exitCode, _exitStatus) {
            root.locked = exitCode == 0;
            Logger.i("RBW", "Locked: " + root.locked);
        }
    }

    Process {
        id: entriesProcess
        running: false
        command: ["rbw", "list", "--raw"]
        property string entries: ""

        stdout: StdioCollector {
            onStreamFinished: {
                entriesProcess.entries = this.text;
            }
        }

        onExited: function (exitCode, _exitStatus) {
            if (exitCode !== 0) {
                return;
            }
            root.entries = JSON.parse(entriesProcess.entries);
            Logger.i("RBW", `Loaded ${root.entries.length} entries`);
        }
    }

    Process {
        id: getEntryProcess
        running: false

        property string output: ""

        onExited: function (exitCode, _exitStatus) {
            if (exitCode !== 0) {
                Logger.e("RBW", `rbw get failed with ${exitCode}`);
                return;
            }
            Logger.d("RBW", `rbw get successed with ${exitCode}`);
            var entry = JSON.parse(getEntryProcess.output);
            wtypeProcess.type(entry.data.password);
        }

        stdout: StdioCollector {
            onStreamFinished: {
                getEntryProcess.output = this.text;
            }
        }

        function getEntry(passwordId) {
            getEntryProcess.exec(["rbw", "get", passwordId, "--raw"]);
        }
    }

    Process {
        id: wtypeProcess
        running: false

        onExited: function (exitCode, _exitStatus) {
            if (exitCode !== 0) {
                Logger.e("RBW", `Wtype failed with ${exitCode}`);
                return;
            }
            Logger.d("RBW", `Wtype successed with ${exitCode}`);
            root.entryId = "";
            root.passwd = "";
        }

        function type(password) {
            wtypeProcess.exec(["wtype", password]);
        }
    }

    function init() {
        Logger.i("RBW", "Initialized");
        checkUnlockedProcess.running = true;
    }

    function onOpened() {
        checkUnlockedProcess.running = true;
    }

    function onClosed() {
        if (root.entryId) {
            Logger.i("RBW", "Getting entry with ID " + root.entryId);
            getEntryProcess.getEntry(root.entryId);
            root.entryId = "";
        }
    }

    function commands() {
        return [
            {
                "name": ">rbw",
                "description": "RBW launcher plugin",
                "icon": "terminal",
                "isTablerIcon": true,
                "isImage": false,
                "onActivate": function () {
                    launcher.setSearchText(">rbw ");
                }
            }
        ];
    }

    function getResults(query) {
        if (!query.startsWith(">rbw"))
            return [];

        if (root.locked) {
            return [
                {
                    "name": "Unlock",
                    "description": "Unlock to list entries",
                    "icon": "lock",
                    "isTablerIcon": false,
                    "isImage": false,
                    "onActivate": function () {
                        Logger.i("RBW", "Unlocking");
                        launcher.close();
                        unlockProcess.running = true;
                    }
                }
            ];
        }

        let expression = query.substring(4).trim().toLowerCase();
        var filtered = root.entries.filter(entry => {
            return entry.name.toLowerCase().includes(expression) ||
                   (entry.user && entry.user.toLowerCase().includes(expression));
        }).map(entry => {
            // Capture entryId by value using an IIFE to avoid closure issues
            return (function(entryId, entryName, entryUser) {
                return {
                    "name": entryName,
                    "description": entryUser,
                    "icon": 'password-copy',
                    "isTablerIcon": false,
                    "isImage": false,
                    "onActivate": function () {
                        root.entryId = entryId;
                        launcher.close();
                    }
                };
            })(entry.id, entry.name, entry.user);
        });
        filtered.push({
            "name": "Lock",
            "description": "Lock rbw agent",
            "icon": "lock",
            "isTablerIcon": false,
            "isImage": false,
            "onActivate": function () {
                Logger.i("RBW", "Locking");
                launcher.close();
                lockProcess.running = true;
            }
        });
        filtered.sort((a, b) => {
            const nameA = a.name.toLowerCase();
            const nameB = b.name.toLowerCase();
            if (nameA < nameB) {
                return -1;
            }
            if (nameA > nameB) {
                return 1;
            }
            // names must be equal
            return 0;
        });
        return filtered;
    }
}

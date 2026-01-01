import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins
import qs.Widgets

PluginComponent {
    id: root

    property bool hasMediaDevices: false
    property bool sleepInhibited: false
    property string mode: "auto" // "auto" or "manual"
    property bool isChangingState: false // Track if we're currently changing state ourselves
    
    onSleepInhibitedChanged: {
        console.log("sleepInhibited changed to:", sleepInhibited)
    }
    
    // Popout content for mode selection
    popoutContent: Component {
        PopoutComponent {
            id: popout
            
            headerText: "Latte"
            detailsText: "Select auto for when a media player is detected, select manual to toggle sleep inhibition manually"
            showCloseButton: true
            
            Column {
                width: parent.width
                spacing: Theme.spacingS
                
                StyledRect {
                    width: parent.width
                    height: 44
                    color: autoMouseArea.containsMouse ? Theme.surfaceContainerHighest : (root.mode === "auto" ? Theme.primary : Theme.surfaceContainerHigh)
                    radius: Theme.cornerRadius
                    border.width: 0
                    
                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Auto (Media Detection)"
                        color: root.mode === "auto" ? Theme.onPrimary : Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }
                    
                    MouseArea {
                        id: autoMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.mode = "auto"
                        }
                    }
                }
                
                StyledRect {
                    width: parent.width
                    height: 44
                    color: manualMouseArea.containsMouse ? Theme.surfaceContainerHighest : (root.mode === "manual" ? Theme.primary : Theme.surfaceContainerHigh)
                    radius: Theme.cornerRadius
                    border.width: 0
                    
                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Manual (On/Off)"
                        color: root.mode === "manual" ? Theme.onPrimary : Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }
                    
                    MouseArea {
                        id: manualMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.mode = "manual"
                        }
                    }
                }
                
                // Toggle button for manual mode
                StyledRect {
                    width: parent.width
                    height: 44
                    visible: root.mode === "manual"
                    color: toggleMouseArea.containsMouse ? Theme.surfaceContainerHighest : (root.sleepInhibited ? Theme.primary : Theme.surfaceContainerHigh)
                    radius: Theme.cornerRadius
                    border.width: 0
                    
                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.sleepInhibited ? "Disable Sleep Inhibition" : "Enable Sleep Inhibition"
                        color: root.sleepInhibited ? Theme.onPrimary : Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }
                    
                    MouseArea {
                        id: toggleMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.handleClick()
                        }
                    }
                }
            }
        }
    }

    // Bar indicator for horizontal bar
    horizontalBarPill: Component {
        DankIcon {
            name: "coffee"
            color: root.sleepInhibited ? Theme.primary : Theme.surfaceText
            size: 20
            opacity: root.sleepInhibited ? 1.0 : 0.3
        }
    }

    // Bar indicator for vertical bar
    verticalBarPill: Component {
        DankIcon {
            name: "coffee"
            color: root.sleepInhibited ? Theme.primary : Theme.surfaceText
            size: 20
            opacity: root.sleepInhibited ? 1.0 : 0.3
        }
    }

    // Timer to periodically check for media devices
    Timer {
        id: checkTimer
        interval: 2000 // Check every 2 seconds
        running: true
        repeat: true
        onTriggered: checkMediaDevices()
    }

    // Process to check for media devices
    Process {
        id: mprisCheckProcess
        command: ["dms", "ipc", "call", "mpris", "list"]

        property string output: ""

        stdout: SplitParser {
            onRead: line => {
                mprisCheckProcess.output += line + "\n"
            }
        }

        onExited: {
            var trimmed = output.trim()
            // Check if there are any media players
            // Handle empty output, empty JSON arrays, null, etc.
            var hasMedia = trimmed !== "" && 
                          trimmed !== "[]" && 
                          trimmed !== "null" && 
                          trimmed !== "{}" &&
                          !trimmed.match(/^\s*\[\s*\]\s*$/) // Empty JSON array with whitespace
            
            if (hasMedia !== root.hasMediaDevices) {
                root.hasMediaDevices = hasMedia
                updateSleepInhibition()
            }
            output = "" // Reset for next run
        }

        stderr: SplitParser {
            onRead: line => {
                if (line.trim()) {
                    console.warn("MPRIS check error:", line)
                }
            }
        }
    }

    // Process to enable sleep inhibition
    Process {
        id: inhibitEnableProcess
        command: ["dms", "ipc", "call", "inhibit", "enable"]

        stdout: SplitParser {
            onRead: line => {
                console.log("Inhibit enable response:", line)
            }
        }

        stderr: SplitParser {
            onRead: line => {
                if (line.trim()) {
                    console.error("Inhibit enable error:", line)
                }
            }
        }

        onExited: (exitCode) => {
            if (exitCode === 0) {
                console.log("Sleep inhibition successfully enabled")
                root.sleepInhibited = true
            } else {
                console.error("Failed to enable sleep inhibition, exit code:", exitCode)
            }
            root.isChangingState = false
        }
    }

    // Process to disable sleep inhibition
    Process {
        id: inhibitDisableProcess
        command: ["dms", "ipc", "call", "inhibit", "disable"]

        stdout: SplitParser {
            onRead: line => {
                console.log("Inhibit disable response:", line)
            }
        }

        stderr: SplitParser {
            onRead: line => {
                if (line.trim()) {
                    console.error("Inhibit disable error:", line)
                }
            }
        }

        onExited: (exitCode) => {
            if (exitCode === 0) {
                console.log("Sleep inhibition successfully disabled")
                root.sleepInhibited = false
            } else {
                console.error("Failed to disable sleep inhibition, exit code:", exitCode)
            }
            root.isChangingState = false
        }
    }

    function checkMediaDevices() {
        mprisCheckProcess.running = true
    }

    function updateSleepInhibition() {
        // Only auto-update if in auto mode
        if (root.mode !== "auto") {
            return
        }
        
        if (root.hasMediaDevices && !root.sleepInhibited) {
            // Enable sleep inhibition
            console.log("Enabling sleep inhibition (media device detected)")
            root.isChangingState = true
            // Update icon immediately
            root.sleepInhibited = true
            // Stop process if already running
            if (inhibitEnableProcess.running) {
                inhibitEnableProcess.running = false
            }
            // Wait a moment then start
            Qt.callLater(() => {
                inhibitEnableProcess.running = true
            })
        } else if (!root.hasMediaDevices && root.sleepInhibited) {
            // Disable sleep inhibition
            console.log("Disabling sleep inhibition (no media devices)")
            root.isChangingState = true
            // Update icon immediately
            root.sleepInhibited = false
            // Stop process if already running
            if (inhibitDisableProcess.running) {
                inhibitDisableProcess.running = false
            }
            // Wait a moment then start
            Qt.callLater(() => {
                inhibitDisableProcess.running = true
            })
        }
    }
    
    function handleClick() {
        if (root.mode === "manual") {
            // Toggle sleep inhibition manually
            if (root.sleepInhibited) {
                root.disableSleepInhibition()
            } else {
                root.enableSleepInhibition()
            }
        }
    }
    
    function enableSleepInhibition() {
        console.log("Manually enabling sleep inhibition")
        root.isChangingState = true
        root.sleepInhibited = true
        if (inhibitEnableProcess.running) {
            inhibitEnableProcess.running = false
        }
        Qt.callLater(() => {
            inhibitEnableProcess.running = true
        })
    }
    
    function disableSleepInhibition() {
        console.log("Manually disabling sleep inhibition")
        root.isChangingState = true
        root.sleepInhibited = false
        if (inhibitDisableProcess.running) {
            inhibitDisableProcess.running = false
        }
        Qt.callLater(() => {
            inhibitDisableProcess.running = true
        })
    }
    
    function showPopout() {
        // Access the variant to show the popout
        // Try to find the variant that has the showPopout method
        if (root.variants) {
            for (var i = 0; i < root.variants.length; i++) {
                var variant = root.variants[i]
                if (variant) {
                    // Try different possible method names
                    if (typeof variant.showPopout === "function") {
                        variant.showPopout()
                        return
                    } else if (typeof variant.openPopout === "function") {
                        variant.openPopout()
                        return
                    } else if (variant.popout && typeof variant.popout.open === "function") {
                        variant.popout.open()
                        return
                    }
                }
            }
        }
        console.warn("Could not find popout method to show popout")
    }

    Component.onCompleted: {
        console.info("InhibitSleep plugin started")
        // Initial check
        checkMediaDevices()
    }

    Component.onDestruction: {
        // Disable sleep inhibition when plugin is destroyed
        if (root.sleepInhibited) {
            inhibitDisableProcess.running = true
        }
    }
}

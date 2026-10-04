import Quickshell.Io
import QtQuick

// Runs a command once, hands its output and exit code to `done`, and goes
// away. Create with `component.createObject(parent, { command: [...], done: ... })`.
Process {
    id: root

    // function(output, exitCode)
    property var done: null
    property int code: -1
    property bool exited: false
    property bool read: false

    function finish() {
        if (!exited || !read)
            return;
        if (done)
            done(output.text, code);
        destroy();
    }

    running: true
    stdout: StdioCollector {
        id: output

        onStreamFinished: {
            root.read = true;
            root.finish();
        }
    }
    onExited: exitCode => {
        code = exitCode;
        exited = true;
        finish();
    }
}

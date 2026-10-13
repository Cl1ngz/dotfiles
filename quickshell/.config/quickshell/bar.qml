//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import qs.bar

ShellRoot {
    // Lets an external command force a config reload:
    //   qs -p ~/.config/quickshell/bar.qml ipc call theme reload

    // Quickshell does watch its files, but a generated Colors.qml can be
    // seen mid-write and the reload then fails silently, leaving the old
    // colours. An explicit call after matugen finishes is deterministic.
    IpcHandler {
        function reload() : string {
            Quickshell.reloadConfig(true);
            return "reloading";
        }

        target: "theme"
    }

    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData

            screen: modelData
        }

    }

}

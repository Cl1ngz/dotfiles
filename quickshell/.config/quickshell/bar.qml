//@ pragma UseQApplication
import Quickshell
import qs.bar

ShellRoot {
    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData
            screen: modelData
        }
    }
}

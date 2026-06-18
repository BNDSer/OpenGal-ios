import Foundation

enum ANSIStripper {
    // Strips ESC[...m CSI sequences, OSC sequences, and normalises line endings
    static func strip(_ input: String) -> String {
        var s = input
        // CSI sequences: ESC [ ... <letter>
        s = s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]",
                                   with: "", options: .regularExpression)
        // OSC sequences: ESC ] ... BEL
        s = s.replacingOccurrences(of: "\u{1B}\\][^\u{07}]*\u{07}",
                                   with: "", options: .regularExpression)
        // Standalone ESC sequences (e.g. ESC = ESC >)
        s = s.replacingOccurrences(of: "\u{1B}[=>]", with: "",
                                   options: .regularExpression)
        // Carriage returns
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")
        // Remove lone ESC characters
        s = s.replacingOccurrences(of: "\u{1B}", with: "")
        return s
    }
}

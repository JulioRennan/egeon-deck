import AppKit

extension WorkbenchColor {
    var nsColor: NSColor {
        NSColor(calibratedRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}

import SwiftUI

extension Double {
    /// Format UV index for display: "5.7" or "0" for zero
    var uvFormatted: String {
        if self == 0 { return "0" }
        if self == self.rounded() { return String(format: "%.0f", self) }
        return String(format: "%.1f", self)
    }
}

extension Date {
    var shortTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: self)
    }

    var hourString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter.string(from: self).lowercased()
    }
}

extension View {
    func clayPanel(isDark: Bool = false) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isDark ? ClayColors.panelBackgroundDark : ClayColors.panelBackground)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            )
    }
}

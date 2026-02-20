import SwiftUI

struct DateSeparatorView: View {
    let date: Date?

    var body: some View {
        HStack(spacing: 12) {
            VStack { Divider() }
            Text(DateFormatting.formatDateOnly(date))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .fixedSize()
            VStack { Divider() }
        }
        .padding(.vertical, 12)
    }
}

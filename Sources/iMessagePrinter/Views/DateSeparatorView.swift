import SwiftUI

struct DateSeparatorView: View {
    let date: Date?

    var body: some View {
        HStack {
            Rectangle()
                .fill(.separator)
                .frame(height: 1)

            Text(DateFormatting.formatDateOnly(date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)

            Rectangle()
                .fill(.separator)
                .frame(height: 1)
        }
        .padding(.vertical, 8)
    }
}

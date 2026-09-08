import SwiftUI

public struct HeliCard<Content: View>: View {
    public var cornerRadius: CGFloat
    public var backgroundColor: Color
    public var content: () -> Content

    public init(
        cornerRadius: CGFloat = 26,
        backgroundColor: Color = HeliColors.cardWarmWhite,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.backgroundColor = backgroundColor
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(HeliColors.sageRule.opacity(0.6), lineWidth: 0.8)
        )
    }
}

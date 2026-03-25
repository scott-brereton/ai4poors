// ColorExtensions.swift
// Ai4Poors - Centralized color definitions, spacing, and design tokens

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Design Tokens

enum Ai4PoorsDesign {
    // Corner radii — consistent hierarchy
    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let overlay: CGFloat = 20
    }

    // Spacing — systematic scale
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    // Icon sizes — consistent across views
    enum IconSize {
        static let tiny: CGFloat = 12
        static let small: CGFloat = 18
        static let medium: CGFloat = 22
        static let large: CGFloat = 32
        static let hero: CGFloat = 40
    }
}

// MARK: - Card Modifier

struct Ai4PoorsCardModifier: ViewModifier {
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.large))
            .shadow(
                color: .black.opacity(elevated ? 0.10 : 0.04),
                radius: elevated ? 12 : 6,
                y: elevated ? 4 : 2
            )
    }
}

extension View {
    func ai4poorsCard(elevated: Bool = false) -> some View {
        modifier(Ai4PoorsCardModifier(elevated: elevated))
    }
}

// MARK: - Tap Feedback Modifier

struct TapFeedbackModifier: ViewModifier {
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

extension View {
    func tapFeedback() -> some View {
        modifier(TapFeedbackModifier())
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if isShowing {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Ai4PoorsDesign.Spacing.lg)
                    .padding(.vertical, Ai4PoorsDesign.Spacing.sm)
                    .background(Color(UIColor.systemGray))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, Ai4PoorsDesign.Spacing.xl)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeOut(duration: 0.25)) { isShowing = false }
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: isShowing)
    }
}

extension View {
    func toast(isShowing: Binding<Bool>, message: String) -> some View {
        modifier(ToastModifier(isShowing: isShowing, message: message))
    }
}

// MARK: - Channel Colors

extension Ai4PoorsChannel {
    var color: Color {
        switch self {
        case .keyboard: return .blue
        case .safari: return .cyan
        case .screenshot: return .indigo
        case .share: return .orange
        case .clipboard: return .purple
        case .message: return .green
        case .reader: return .brown
        }
    }

    var tintBackground: Color {
        color.opacity(0.10)
    }
}

extension TranscriptionMode {
    var color: Color {
        switch self {
        case .plain: return .blue
        case .aiCleanup: return .purple
        }
    }
}

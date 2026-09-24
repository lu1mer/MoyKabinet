import SwiftUI

/// An in-app launch transition. The system launch screen remains static by iOS design.
struct LaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bloom = false
    @State private var shine = false

    var body: some View {
        ZStack {
            Style.background.ignoresSafeArea()

            Circle()
                .fill(Style.accent.opacity(0.12))
                .frame(width: 330, height: 330)
                .blur(radius: 45)
                .scaleEffect(bloom ? 1.2 : 0.68)
                .opacity(bloom ? 1 : 0.3)

            Circle()
                .strokeBorder(Style.accent.opacity(0.10), lineWidth: 1)
                .frame(width: 270, height: 270)
                .scaleEffect(bloom ? 1 : 0.7)
            Circle()
                .strokeBorder(Style.accent.opacity(0.20), lineWidth: 1)
                .frame(width: 200, height: 200)
                .scaleEffect(bloom ? 1 : 0.72)

            VStack(spacing: 27) {
                ZStack(alignment: .topTrailing) {
                    Text("м")
                        .font(.system(size: 103, weight: .black, design: .rounded))
                        .tracking(-11)
                        .foregroundStyle(Style.gradient)
                        .frame(width: 120, height: 116)
                    Circle()
                        .fill(Style.hotPink)
                        .frame(width: 17, height: 17)
                        .offset(x: 16, y: 71)
                }
                .scaleEffect(bloom ? 1 : 0.66)
                .rotationEffect(.degrees(bloom ? 0 : -12))

                Text("МОЙ КАБИНЕТ")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(3.3)
                    .foregroundStyle(Style.ink)
                .opacity(shine ? 1 : 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Мой кабинет, загрузка")

            VStack {
                Spacer()
                Capsule()
                    .fill(Style.line)
                    .frame(width: 78, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Style.gradient)
                            .frame(width: shine ? 78 : 12, height: 3)
                    }
                    .padding(.bottom, 38)
            }
        }
        .onAppear {
            if reduceMotion { bloom = true; shine = true }
            else {
                withAnimation(.spring(response: 0.62, dampingFraction: 0.74)) { bloom = true }
                withAnimation(.easeOut(duration: 0.68).delay(0.10)) { shine = true }
            }
        }
    }
}

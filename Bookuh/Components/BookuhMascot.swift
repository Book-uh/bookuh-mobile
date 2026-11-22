import SwiftUI

struct BookuhMascot: View {
    let size: CGFloat
    var animates = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFloating = false

    var body: some View {
        Group {
            if animates {
                artwork
                    .offset(y: reduceMotion ? 0 : isFloating ? -2 : 2)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                        value: isFloating
                    )
                    .onAppear { isFloating = !reduceMotion }
                    .onChange(of: reduceMotion) { _, value in isFloating = !value }
            } else {
                artwork
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("독서 매니저 북어")
    }

    private var artwork: some View {
        ZStack {
            Circle().fill(BookuhTheme.green)
            Canvas { context, canvasSize in
                let x = canvasSize.width / 32
                let y = canvasSize.height / 28

                // 화면 시안 v2의 공통 fish 벡터와 같은 좌표다.
                var fish = Path()
                fish.move(to: CGPoint(x: 3 * x, y: 16 * y))
                fish.addCurve(
                    to: CGPoint(x: 24 * x, y: 12 * y),
                    control1: CGPoint(x: 9 * x, y: 8 * y),
                    control2: CGPoint(x: 18 * x, y: 7 * y)
                )
                fish.addLine(to: CGPoint(x: 29 * x, y: 8.5 * y))
                fish.addLine(to: CGPoint(x: 27.5 * x, y: 14 * y))
                fish.addLine(to: CGPoint(x: 29 * x, y: 19.5 * y))
                fish.addLine(to: CGPoint(x: 24 * x, y: 16 * y))
                fish.addCurve(
                    to: CGPoint(x: 3 * x, y: 16 * y),
                    control1: CGPoint(x: 18 * x, y: 21 * y),
                    control2: CGPoint(x: 9 * x, y: 20 * y)
                )
                fish.closeSubpath()
                context.fill(fish, with: .color(Color(
                    red: 253 / 255.0, green: 251 / 255.0, blue: 242 / 255.0
                )))

                let eye = Path(ellipseIn: CGRect(
                    x: (9.5 - 1.4) * x, y: (13.8 - 1.4) * y,
                    width: 2.8 * x, height: 2.8 * y
                ))
                context.fill(eye, with: .color(BookuhTheme.green))
            }
            .frame(width: size * 0.64, height: size * 0.56)
            .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
    }
}

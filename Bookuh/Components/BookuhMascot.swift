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
            BookuhFish(
                bodyColor: Color(red: 253 / 255.0, green: 251 / 255.0, blue: 242 / 255.0),
                eyeColor: BookuhTheme.green
            )
            .frame(width: size * 0.64, height: size * 0.56)
            .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
    }
}

struct BookuhReadingIllustration: View {
    let width: CGFloat

    var body: some View {
        ZStack {
            Ellipse()
                .fill(BookuhTheme.paperDeep)
                .frame(width: width * 0.82, height: width * 0.69)
            BookuhFish(bodyColor: BookuhTheme.green, eyeColor: BookuhTheme.paper, headY: 14)
                .frame(width: width * 0.67, height: width * 0.55)
                .offset(y: -width * 0.1)
            openBook
                .frame(width: width * 0.89, height: width * 0.38)
                .offset(y: width * 0.12)
        }
        .frame(width: width, height: width * 0.76)
        .accessibilityHidden(true)
    }

    private var openBook: some View {
        Canvas { context, size in
            let x = size.width / 160
            let y = size.height / 80
            func point(_ horizontal: CGFloat, _ vertical: CGFloat) -> CGPoint {
                CGPoint(x: horizontal * x, y: vertical * y)
            }

            let mirrored = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: size.width, ty: 0)
            var page = Path()
            page.move(to: point(18, 13))
            page.addQuadCurve(to: point(80, 26), control: point(51, 5))
            page.addLine(to: point(80, 69))
            page.addQuadCurve(to: point(8, 56), control: point(44, 52))
            page.closeSubpath()
            let rightPage = page.applying(mirrored)

            var cover = page
            cover.addPath(rightPage)
            context.fill(cover.applying(CGAffineTransform(translationX: 0, y: 6 * y)),
                         with: .color(BookuhTheme.walnut))
            context.fill(page, with: .color(BookuhTheme.card))
            context.fill(rightPage, with: .color(BookuhTheme.paper))
            context.stroke(cover, with: .color(BookuhTheme.line),
                           style: StrokeStyle(lineWidth: 1.2 * x, lineJoin: .round))

            var lines = Path()
            lines.move(to: point(26, 27))
            lines.addQuadCurve(to: point(65, 34), control: point(48, 25))
            lines.move(to: point(23, 38))
            lines.addQuadCurve(to: point(65, 44), control: point(47, 36))
            lines.addPath(lines.applying(mirrored))
            context.stroke(lines, with: .color(BookuhTheme.line),
                           style: StrokeStyle(lineWidth: 1.3 * x, lineCap: .round))
        }
    }
}

private struct BookuhFish: View {
    let bodyColor: Color
    let eyeColor: Color
    var headY: CGFloat = 16

    var body: some View {
        Canvas { context, size in
            let x = size.width / 32
            let y = size.height / 28

            // 화면 시안 v2의 공통 fish 벡터와 같은 좌표다.
            var fish = Path()
            let head = CGPoint(x: 3 * x, y: headY * y)
            fish.move(to: head)
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
                to: head,
                control1: CGPoint(x: 18 * x, y: 21 * y),
                control2: CGPoint(x: 9 * x, y: 20 * y)
            )
            fish.closeSubpath()
            context.fill(fish, with: .color(bodyColor))

            let eye = Path(ellipseIn: CGRect(
                x: (9.5 - 1.4) * x, y: (13.8 - 1.4) * y,
                width: 2.8 * x, height: 2.8 * y
            ))
            context.fill(eye, with: .color(eyeColor))
        }
    }
}

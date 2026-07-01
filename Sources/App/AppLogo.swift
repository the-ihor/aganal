import SwiftUI

/// AGANAL's own logomark: a magnifying glass inspecting a bar chart, with the
/// magnified bar rendered in analytic blue. Built natively (gradients, glow,
/// glass highlights) rather than as a flat vector so it matches the app icon.
///
/// The geometry is authored on the same 1024 grid as the rendered icon and
/// placed through the icon's centering transform (visual centroid → centre,
/// uniform fill scale), so the in-app badge and the `.icns` stay visually
/// identical.
struct AppLogo: View {
    var size: CGFloat = 28
    var palette: LogoPalette = .dark

    var body: some View {
        LogoBadge(palette: palette)
            .frame(width: 1024, height: 1024)
            .scaleEffect(size / 1024)
            .frame(width: size, height: size)
            .accessibilityLabel(Text("AGANAL"))
    }
}

// MARK: - Centering transform (from the icon renderer)

private let kCentroidX: CGFloat = 497.78
private let kCentroidY: CGFloat = 440.95
private let kScale: CGFloat = 0.8878

private func gx(_ v: CGFloat) -> CGFloat { (v - kCentroidX) * kScale + 512 }
private func gy(_ v: CGFloat) -> CGFloat { (v - kCentroidY) * kScale + 512 }
private func gs(_ v: CGFloat) -> CGFloat { v * kScale }

// MARK: - Badge (squircle background + mark)

private struct LogoBadge: View {
    let palette: LogoPalette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 232, style: .continuous)
                .fill(LinearGradient(colors: [palette.bgTop, palette.bgBot],
                                     startPoint: .top, endPoint: .bottom))
            LogoMark(p: palette)
                .shadow(color: palette.shadow, radius: gs(16), y: gs(11))
        }
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - The mark

private struct Bar { let cx: CGFloat; let h: CGFloat }

private struct LogoMark: View {
    let p: LogoPalette

    private let bars = [Bar(cx: 190, h: 200), Bar(cx: 286, h: 300),
                        Bar(cx: 382, h: 240), Bar(cx: 478, h: 400),
                        Bar(cx: 574, h: 300)]

    var body: some View {
        ZStack {
            // background chart bars
            ForEach(bars.indices, id: \.self) { i in
                let b = bars[i]
                RoundedRectangle(cornerRadius: gs(15), style: .continuous)
                    .fill(LinearGradient(colors: [p.barTop, p.barBot],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: gs(64), height: gs(b.h))
                    .position(x: gx(b.cx), y: gy(700 - b.h / 2))
            }
            // baseline
            Capsule()
                .fill(p.ink)
                .frame(width: gs(628 - 150), height: gs(24))
                .position(x: gx((150 + 628) / 2), y: gy(700))

            // magnifier handle (behind the ring)
            Capsule()
                .fill(p.ink)
                .frame(width: gs(214), height: gs(56))
                .rotationEffect(.degrees(50))
                .position(x: gx(736.8), y: gy(540.6))

            // lens interior (glass + magnified bars + highlights)
            LensInterior(p: p)
                .frame(width: gs(328), height: gs(328))
                .position(x: gx(560), y: gy(330))

            // magnifier ring
            Circle()
                .strokeBorder(p.ink, lineWidth: gs(48))
                .frame(width: gs(392), height: gs(392))
                .position(x: gx(560), y: gy(330))
        }
        .frame(width: 1024, height: 1024)
    }
}

/// Content seen "through" the lens, clipped to the glass circle: a soft blue
/// glow, the dominant magnified blue bar, a smaller ink neighbour, and the
/// glass specular highlights.
private struct LensInterior: View {
    let p: LogoPalette

    var body: some View {
        ZStack {
            Circle().fill(p.glass)

            RoundedRectangle(cornerRadius: gs(55))
                .fill(p.blueTop)
                .opacity(0.5)
                .frame(width: gs(130), height: gs(250))
                .offset(x: gs(28), y: gs(-5))
                .blur(radius: gs(22))

            RoundedRectangle(cornerRadius: gs(13), style: .continuous)
                .fill(LinearGradient(colors: [p.barTop, p.barBot],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: gs(52), height: gs(150))
                .offset(x: gs(-60), y: gs(45))

            RoundedRectangle(cornerRadius: gs(24), style: .continuous)
                .fill(LinearGradient(colors: [p.blueTop, p.blueBot],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: gs(100), height: gs(250))
                .offset(x: gs(32), y: gs(-5))

            Ellipse()
                .fill(.white.opacity(0.26))
                .frame(width: gs(134), height: gs(116))
                .offset(x: gs(-73), y: gs(-92))
                .blur(radius: gs(22))

            RoundedRectangle(cornerRadius: gs(17), style: .continuous)
                .fill(.white.opacity(0.32))
                .frame(width: gs(34), height: gs(220))
                .rotationEffect(.degrees(-32))
                .offset(x: gs(-60), y: gs(-28))
                .blur(radius: gs(3))
        }
        .clipShape(Circle())
    }
}

// MARK: - Palette

/// Colour scheme for the mark. `.dark` is the primary treatment (works on any
/// window chrome); `.light` mirrors the light app-icon render.
struct LogoPalette {
    var ink: Color
    var barTop: Color
    var barBot: Color
    var glass: Color
    var blueTop: Color
    var blueBot: Color
    var bgTop: Color
    var bgBot: Color
    var shadow: Color

    static let dark = LogoPalette(
        ink: rgb(244, 246, 252),
        barTop: rgb(150, 156, 182), barBot: rgb(110, 116, 146),
        glass: rgb(48, 51, 68),
        blueTop: rgb(128, 141, 255), blueBot: rgb(58, 70, 214),
        bgTop: rgb(40, 42, 54), bgBot: rgb(18, 19, 27),
        shadow: .black.opacity(0.35))

    static let light = LogoPalette(
        ink: rgb(28, 29, 38),
        barTop: rgb(66, 68, 84), barBot: rgb(26, 27, 36),
        glass: rgb(236, 239, 249),
        blueTop: rgb(128, 141, 255), blueBot: rgb(58, 70, 214),
        bgTop: rgb(252, 252, 254), bgBot: rgb(232, 235, 244),
        shadow: .black.opacity(0.16))
}

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(red: r / 255, green: g / 255, blue: b / 255)
}

#Preview {
    HStack(spacing: 24) {
        AppLogo(size: 96, palette: .dark)
        AppLogo(size: 96, palette: .light)
        AppLogo(size: 28)
        AppLogo(size: 18)
    }
    .padding()
}

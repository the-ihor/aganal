import SwiftUI

/// Minimal SVG path-data (`d`) parser producing a SwiftUI `Path` in the path's
/// own coordinate space (y-down, matching SwiftUI). Supports M/L/H/V/C/S/Q/T/A/Z
/// in absolute and relative forms — enough to render icon geometry faithfully,
/// including elliptical arcs (approximated with cubic Béziers).
enum SVGPath {
    static func path(from d: String) -> Path {
        var scanner = Scanner(Array(d))
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var previousControl: CGPoint?
        var command: Character = " "
        var previousCommand: Character = " "
        var guardCounter = 0
        let guardLimit = d.count * 4 + 16

        while true {
            guardCounter += 1
            if guardCounter > guardLimit { break }   // malformed-input backstop
            scanner.skipSeparators()
            if scanner.isAtEnd { break }

            if scanner.peekIsCommand {
                command = scanner.readCommand()
            } else if command == "M" {
                command = "L"            // extra coordinate pairs after M are implicit L
            } else if command == "m" {
                command = "l"
            } else if command == " " {
                break                     // coordinates with no command: malformed
            }

            switch command {
            case "M":
                current = scanner.point()
                path.move(to: current); subpathStart = current
            case "m":
                current = scanner.point(relativeTo: current)
                path.move(to: current); subpathStart = current
            case "L":
                current = scanner.point(); path.addLine(to: current)
            case "l":
                current = scanner.point(relativeTo: current); path.addLine(to: current)
            case "H":
                current.x = CGFloat(scanner.number()); path.addLine(to: current)
            case "h":
                current.x += CGFloat(scanner.number()); path.addLine(to: current)
            case "V":
                current.y = CGFloat(scanner.number()); path.addLine(to: current)
            case "v":
                current.y += CGFloat(scanner.number()); path.addLine(to: current)
            case "C", "c":
                let origin = command == "c" ? current : .zero
                let control1 = scanner.point(relativeTo: origin)
                let control2 = scanner.point(relativeTo: origin)
                let end = scanner.point(relativeTo: origin)
                path.addCurve(to: end, control1: control1, control2: control2)
                previousControl = control2; current = end
            case "S", "s":
                let origin = command == "s" ? current : .zero
                let control1 = reflected(previousControl, about: current,
                                         previousCommand: previousCommand, cubic: true)
                let control2 = scanner.point(relativeTo: origin)
                let end = scanner.point(relativeTo: origin)
                path.addCurve(to: end, control1: control1, control2: control2)
                previousControl = control2; current = end
            case "Q", "q":
                let origin = command == "q" ? current : .zero
                let control = scanner.point(relativeTo: origin)
                let end = scanner.point(relativeTo: origin)
                path.addQuadCurve(to: end, control: control)
                previousControl = control; current = end
            case "T", "t":
                let origin = command == "t" ? current : .zero
                let control = reflected(previousControl, about: current,
                                        previousCommand: previousCommand, cubic: false)
                let end = scanner.point(relativeTo: origin)
                path.addQuadCurve(to: end, control: control)
                previousControl = control; current = end
            case "A", "a":
                let origin = command == "a" ? current : .zero
                let rx = scanner.number(), ry = scanner.number()
                let rotation = scanner.number()
                let largeArc = scanner.flag(), sweep = scanner.flag()
                let end = scanner.point(relativeTo: origin)
                appendArc(&path, from: current, to: end, rx: rx, ry: ry,
                          rotationDegrees: rotation, largeArc: largeArc, sweep: sweep)
                current = end
            case "Z", "z":
                path.closeSubpath(); current = subpathStart
            default:
                return path               // unknown command: stop safely
            }

            if !"CcSsQqTt".contains(command) { previousControl = nil }
            previousCommand = command
        }
        return path
    }

    /// Reflection of the previous control point about the current point, used
    /// for the smooth-curve commands (S/T). Falls back to the current point when
    /// the previous command wasn't a matching curve.
    private static func reflected(_ previous: CGPoint?, about current: CGPoint,
                                  previousCommand: Character, cubic: Bool) -> CGPoint {
        let compatible = cubic ? "CcSs" : "QqTt"
        guard let previous, compatible.contains(previousCommand) else { return current }
        return CGPoint(x: 2 * current.x - previous.x, y: 2 * current.y - previous.y)
    }

    // MARK: - Elliptical arc → cubic Béziers (SVG implementation notes F.6)

    private static func appendArc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint,
                                  rx rxIn: Double, ry ryIn: Double,
                                  rotationDegrees: Double, largeArc: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        let x0 = Double(p0.x), y0 = Double(p0.y), xe = Double(p1.x), ye = Double(p1.y)
        if rx == 0 || ry == 0 || (x0 == xe && y0 == ye) {
            path.addLine(to: p1); return
        }
        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        let dx = (x0 - xe) / 2, dy = (y0 - ye) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        var rxs = rx * rx, rys = ry * ry
        let x1ps = x1p * x1p, y1ps = y1p * y1p
        let lambda = x1ps / rxs + y1ps / rys
        if lambda > 1 {
            let s = sqrt(lambda); rx *= s; ry *= s; rxs = rx * rx; rys = ry * ry
        }

        var numerator = rxs * rys - rxs * y1ps - rys * x1ps
        let denominator = rxs * y1ps + rys * x1ps
        if numerator < 0 { numerator = 0 }
        var coefficient = denominator == 0 ? 0 : sqrt(numerator / denominator)
        if largeArc == sweep { coefficient = -coefficient }
        let cxp = coefficient * (rx * y1p / ry)
        let cyp = coefficient * -(ry * x1p / rx)

        let cx = cosPhi * cxp - sinPhi * cyp + (x0 + xe) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (y0 + ye) / 2

        let ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry
        let theta1 = angle(1, 0, ux, uy)
        var delta = angle(ux, uy, vx, vy)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(Int(ceil(abs(delta) / (.pi / 2))), 1)
        let step = delta / Double(segments)
        let handle = 4.0 / 3.0 * tan(step / 4)
        var angleStart = theta1
        for _ in 0..<segments {
            let angleEnd = angleStart + step
            let start = ellipse(cx, cy, rx, ry, cosPhi, sinPhi, angleStart)
            let end = ellipse(cx, cy, rx, ry, cosPhi, sinPhi, angleEnd)
            let d0 = derivative(rx, ry, cosPhi, sinPhi, angleStart)
            let d1 = derivative(rx, ry, cosPhi, sinPhi, angleEnd)
            let control1 = CGPoint(x: start.x + handle * d0.x, y: start.y + handle * d0.y)
            let control2 = CGPoint(x: end.x - handle * d1.x, y: end.y - handle * d1.y)
            path.addCurve(to: end, control1: control1, control2: control2)
            angleStart = angleEnd
        }
    }

    private static func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
        let length = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
        guard length > 0 else { return 0 }
        var value = acos(min(max((ux * vx + uy * vy) / length, -1), 1))
        if ux * vy - uy * vx < 0 { value = -value }
        return value
    }

    private static func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double,
                                _ cosPhi: Double, _ sinPhi: Double, _ theta: Double) -> CGPoint {
        let x = rx * cos(theta), y = ry * sin(theta)
        return CGPoint(x: cx + x * cosPhi - y * sinPhi, y: cy + x * sinPhi + y * cosPhi)
    }

    private static func derivative(_ rx: Double, _ ry: Double, _ cosPhi: Double,
                                   _ sinPhi: Double, _ theta: Double) -> CGPoint {
        let dx = -rx * sin(theta), dy = ry * cos(theta)
        return CGPoint(x: dx * cosPhi - dy * sinPhi, y: dx * sinPhi + dy * cosPhi)
    }

    // MARK: - Scanner

    private struct Scanner {
        let chars: [Character]
        var index = 0

        init(_ chars: [Character]) { self.chars = chars }

        var isAtEnd: Bool { index >= chars.count }

        var peekIsCommand: Bool { index < chars.count && chars[index].isLetter }

        mutating func readCommand() -> Character {
            let c = chars[index]; index += 1; return c
        }

        mutating func skipSeparators() {
            while index < chars.count {
                switch chars[index] {
                case " ", ",", "\n", "\t", "\r": index += 1
                default: return
                }
            }
        }

        mutating func number() -> Double {
            skipSeparators()
            var text = ""
            if index < chars.count, chars[index] == "-" || chars[index] == "+" {
                text.append(chars[index]); index += 1
            }
            var seenDot = false
            while index < chars.count {
                let c = chars[index]
                if c >= "0" && c <= "9" {
                    text.append(c); index += 1
                } else if c == "." {
                    if seenDot { break }
                    seenDot = true; text.append(c); index += 1
                } else if c == "e" || c == "E" {
                    text.append(c); index += 1
                    if index < chars.count, chars[index] == "-" || chars[index] == "+" {
                        text.append(chars[index]); index += 1
                    }
                } else { break }
            }
            return Double(text) ?? 0
        }

        /// Arc flags are a single '0'/'1' with no separator required.
        mutating func flag() -> Bool {
            skipSeparators()
            guard index < chars.count else { return false }
            let c = chars[index]; index += 1
            return c == "1"
        }

        mutating func point(relativeTo origin: CGPoint = .zero) -> CGPoint {
            let x = number(), y = number()
            return CGPoint(x: origin.x + CGFloat(x), y: origin.y + CGFloat(y))
        }
    }
}

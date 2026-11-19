import SwiftUI

/// Draws a north-facing sector that the map rotates to the phone heading.
struct HeadingCone: Shape {

    var halfAngle: Double = 30

    /// Centers the sector on the user marker and fits it inside the available bounds.
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        // The unrotated sector points up; the map rotates it by phone heading minus map heading.
        path.addArc(
            center: center, radius: radius, startAngle: .degrees(-90 - halfAngle),
            endAngle: .degrees(-90 + halfAngle), clockwise: false)
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        HeadingCone()
            .fill(.blue.opacity(0.3))

        Circle()
            .fill(.blue)
            .frame(width: 14, height: 14)
    }
    .frame(width: 120, height: 120)
    .padding()
}

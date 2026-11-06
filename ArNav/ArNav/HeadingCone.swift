//
//  HeadingCone.swift
//  ArNav
//
//  Created by Franklyn Adu-Baah on 10/20/26.
//

import SwiftUI
// Creating the cone from shape protocol
struct HeadingCone: Shape {
    
    var halfAngle: Double = 30
    
    //describing shape outline
    func path(in rect: CGRect) -> Path {
        // Sets the center of the cone to the rectangle containing it
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // radius picks the smallest dimension and dividing so it says in the drawing space
        let radius = min(rect.width, rect.height) / 2
        //creates an emppty path
        var path = Path()
        // moves to the center of the drawing space
        path.move(to: center)
        //draws the arc
        path.addArc(center: center, radius: radius, startAngle: .degrees(-90 - halfAngle), endAngle: .degrees(-90 + halfAngle), clockwise: false)
        // closes the path
        path.closeSubpath()
        // returns the drawn path
        return path
    }
}

#Preview {
    ZStack{
        HeadingCone()
            .fill(.blue.opacity(0.3))
        
        Circle()
            .fill(.blue)
            .frame(width: 14, height: 14)
    }
    .frame(width: 120, height: 120)
    .padding()
}

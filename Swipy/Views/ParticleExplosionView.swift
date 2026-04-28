import SwiftUI
import QuartzCore

struct ParticleExplosionView: UIViewRepresentable {
    let origin: CGPoint
    let destination: CGPoint
    let color: UIColor

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        
        // יצירת שכבת החלקיקים
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = origin
        emitter.emitterSize = CGSize(width: 10, height: 10)
        emitter.emitterShape = .circle
        
        let cell = CAEmitterCell()
        cell.birthRate = 80 // פיצוץ עשיר
        cell.lifetime = 1.2
        cell.velocity = 400
        cell.velocityRange = 200
        cell.emissionRange = .pi / 2
        cell.emissionLongitude = -.pi / 4  // כיוון ימין-למעלה
        cell.spin = 4
        cell.spinRange = 2
        cell.scale = 0.05
        cell.scaleRange = 0.1
        cell.scaleSpeed = 0.1
        cell.alphaSpeed = -0.8 // נעלם בהדרגה
        
        // עיצוב החלקיק (אבק נוצץ)
        cell.contents = createParticleImage()
        cell.color = color.cgColor
        
        emitter.emitterCells = [cell]
        view.layer.addSublayer(emitter)
        
        // אנימציה ש"שואבת" את נקודת הפליטה לכיוון המד (Dopamine Meter)
        let animation = CABasicAnimation(keyPath: "emitterPosition")
        animation.fromValue = NSValue(cgPoint: origin)
        animation.toValue = NSValue(cgPoint: destination)
        animation.duration = 0.8
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        
        // עצירת הפיצוץ אחרי חצי שנייה כדי שלא ימשיך לנצח
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    emitter.birthRate = 0
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    emitter.removeFromSuperlayer()
                }
                
                emitter.add(animation, forKey: "flyToMeter")
                
                return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    // פונקציית עזר ליצירת טקסטורת אבק רכה במקום עיגול קשיח
    private func createParticleImage() -> CGImage? {
        let size = CGSize(width: 20, height: 20)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let context = UIGraphicsGetCurrentContext()
        let radialGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])
        context?.drawRadialGradient(radialGradient!, startCenter: CGPoint(x: 10, y: 10), startRadius: 0, endCenter: CGPoint(x: 10, y: 10), endRadius: 10, options: [])
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image?.cgImage
    }
}

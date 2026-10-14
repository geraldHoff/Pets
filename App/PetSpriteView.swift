import PetCore
import SwiftUI

/// Plays a `SpriteAnimation` by swapping frames on a timer.
struct PetSpriteView: View {
    let animation: SpriteAnimation

    var body: some View {
        TimelineView(.periodic(from: .now, by: animation.frameDuration)) { context in
            PixelSpriteCanvas(sprite: animation.frame(at: context.date))
        }
        .aspectRatio(
            CGFloat(animation.frames[0].width) / CGFloat(animation.frames[0].height),
            contentMode: .fit
        )
    }
}

/// Draws one frame as solid squares, so scaling stays nearest-neighbor crisp.
struct PixelSpriteCanvas: View {
    let sprite: PixelSprite

    var body: some View {
        Canvas { context, size in
            let pixel = min(size.width / CGFloat(sprite.width), size.height / CGFloat(sprite.height))
            for y in 0..<sprite.height {
                for x in 0..<sprite.width {
                    guard let char = sprite.character(x: x, y: y),
                          let rgb = PetSprites.palette[char] else { continue }
                    // Pad by a hair so neighbouring squares don't show seams.
                    let rect = CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: pixel + 0.5, height: pixel + 0.5)
                    context.fill(Path(rect), with: .color(Color(rgb)))
                }
            }
        }
    }
}

extension Color {
    init(_ rgb: RGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

import Foundation
import Testing
@testable import PetCore

@Suite struct SpriteTests {
    private var allFrames: [(Mood, Int, PixelSprite)] {
        Mood.allCases.flatMap { mood in
            PetSprites.animation(for: mood).frames.enumerated().map { (mood, $0.offset, $0.element) }
        }
    }

    @Test func everyFrameIsRectangularAndTheSameSize() {
        let reference = PetSprites.animation(for: .happy).frames[0]
        for (mood, index, frame) in allFrames {
            #expect(frame.width == reference.width, "\(mood) frame \(index) width")
            #expect(frame.height == reference.height, "\(mood) frame \(index) height")
            for (y, row) in frame.pixels.enumerated() {
                #expect(row.count == frame.width, "\(mood) frame \(index) row \(y) has \(row.count) pixels")
            }
        }
    }

    @Test func everyPixelIsInThePalette() {
        for (mood, index, frame) in allFrames {
            for row in frame.pixels {
                for char in row where char != PixelSprite.transparent {
                    #expect(PetSprites.palette[char] != nil, "\(mood) frame \(index) uses unknown color '\(char)'")
                }
            }
        }
    }

    @Test func everyAnimationActuallyAnimates() {
        for mood in Mood.allCases {
            let frames = PetSprites.animation(for: mood).frames
            #expect(Set(frames.map { $0.pixels.map { String($0) } }).count > 1, "\(mood) has no visible change")
        }
    }

    @Test func shiftedMovesRowsAndPads() {
        let sprite = PixelSprite(["AB", "CD", ".."])
        #expect(sprite.shifted(dy: -1) == PixelSprite(["CD", "..", ".."]))
        #expect(sprite.shifted(dy: 1) == PixelSprite(["..", "AB", "CD"]))
    }

    @Test func characterLookup() {
        let sprite = PixelSprite(["K.", ".B"])
        #expect(sprite.character(x: 0, y: 0) == "K")
        #expect(sprite.character(x: 1, y: 0) == nil)
        #expect(sprite.character(x: 5, y: 5) == nil)
    }

    @Test func frameAtDateLoops() {
        let a = PixelSprite(["A"]), b = PixelSprite(["B"])
        let animation = SpriteAnimation(frames: [a, b], frameDuration: 0.5)
        #expect(animation.frame(at: Date(timeIntervalSinceReferenceDate: 0)) == a)
        #expect(animation.frame(at: Date(timeIntervalSinceReferenceDate: 0.6)) == b)
        #expect(animation.frame(at: Date(timeIntervalSinceReferenceDate: 1.1)) == a)
        #expect(animation.frame(at: Date(timeIntervalSinceReferenceDate: -0.2)) == b)
    }

    @Test func hexParsing() {
        #expect(RGBColor(hex: "#FF0080") == RGBColor(hex: "ff0080"))
        #expect(RGBColor(hex: "#FF0080")?.red == 1)
        #expect(RGBColor(hex: "#FF0080")?.green == 0)
        #expect(RGBColor(hex: "#12345") == nil)
        #expect(RGBColor(hex: "#GGGGGG") == nil)
    }
}

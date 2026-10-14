import Foundation

public struct RGBColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    /// Parses "#RRGGBB" (the leading # is optional).
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }
}

/// One frame of pixel art, written as rows of palette characters.
/// `.` is transparent. Render with nearest-neighbor scaling only.
public struct PixelSprite: Equatable, Sendable {
    public static let transparent: Character = "."

    public let pixels: [[Character]]

    public init(_ rows: [String]) {
        pixels = rows.map(Array.init)
    }

    public var width: Int { pixels.first?.count ?? 0 }
    public var height: Int { pixels.count }

    /// The palette character at (x, y), or nil if transparent or out of bounds.
    public func character(x: Int, y: Int) -> Character? {
        guard pixels.indices.contains(y), pixels[y].indices.contains(x) else { return nil }
        let char = pixels[y][x]
        return char == Self.transparent ? nil : char
    }

    /// The same art moved up (negative) or down (positive), padded with transparency.
    public func shifted(dy: Int) -> PixelSprite {
        let blank = String(repeating: Self.transparent, count: width)
        let rows = (0..<height).map { y -> String in
            let source = y - dy
            return pixels.indices.contains(source) ? String(pixels[source]) : blank
        }
        return PixelSprite(rows)
    }
}

/// A looping frame sequence.
public struct SpriteAnimation: Equatable, Sendable {
    public let frames: [PixelSprite]
    public let frameDuration: TimeInterval

    public init(frames: [PixelSprite], frameDuration: TimeInterval) {
        precondition(!frames.isEmpty, "An animation needs at least one frame")
        self.frames = frames
        self.frameDuration = frameDuration
    }

    /// The frame to show at `date`, so every view showing this animation stays in sync.
    public func frame(at date: Date) -> PixelSprite {
        let tick = Int((date.timeIntervalSinceReferenceDate / frameDuration).rounded(.down))
        let index = ((tick % frames.count) + frames.count) % frames.count
        return frames[index]
    }
}

/// Placeholder art (a 16x14 blob) until real Aseprite frames replace it.
public enum PetSprites {
    public static let palette: [Character: RGBColor] = [
        "K": RGBColor(hex: "#2B1D3A")!, // outline, eyes, mouth
        "B": RGBColor(hex: "#F7B267")!, // body
        "P": RGBColor(hex: "#F25F5C")!, // cheeks
        "Z": RGBColor(hex: "#7FB7FF")!, // sleep "z"
        "T": RGBColor(hex: "#4EA8DE")!, // tear
    ]

    public static func animation(for mood: Mood) -> SpriteAnimation {
        switch mood {
        case .happy: SpriteAnimation(frames: [happy, happy.shifted(dy: -1)], frameDuration: 0.4)
        case .content: SpriteAnimation(frames: [content, content, content, contentBlink], frameDuration: 0.5)
        case .sleepy: SpriteAnimation(frames: [sleepy, sleepyZ], frameDuration: 1.0)
        case .sad: SpriteAnimation(frames: [sad, sadTearLow], frameDuration: 0.7)
        }
    }

    static let happy = PixelSprite([
        "................",
        "................",
        ".....KKKKKK.....",
        "...KKBBBBBBKK...",
        "..KBBBBBBBBBBK..",
        ".KBBBBBBBBBBBBK.",
        ".KBBBKBBBBKBBBK.",
        ".KBBBKBBBBKBBBK.",
        ".KBPBBBBBBBBPBK.",
        ".KBBBKBBBBKBBBK.",
        ".KBBBBKKKKBBBBK.",
        "..KBBBBBBBBBBK..",
        "...KKKKKKKKKK...",
        "................",
    ])

    static let content = PixelSprite([
        "................",
        "................",
        ".....KKKKKK.....",
        "...KKBBBBBBKK...",
        "..KBBBBBBBBBBK..",
        ".KBBBBBBBBBBBBK.",
        ".KBBBKBBBBKBBBK.",
        ".KBBBKBBBBKBBBK.",
        ".KBPBBBBBBBBPBK.",
        ".KBBBBBBBBBBBBK.",
        ".KBBBBKKKKBBBBK.",
        "..KBBBBBBBBBBK..",
        "...KKKKKKKKKK...",
        "................",
    ])

    static let contentBlink = PixelSprite([
        "................",
        "................",
        ".....KKKKKK.....",
        "...KKBBBBBBKK...",
        "..KBBBBBBBBBBK..",
        ".KBBBBBBBBBBBBK.",
        ".KBBBBBBBBBBBBK.",
        ".KBBKKBBBBKKBBK.",
        ".KBPBBBBBBBBPBK.",
        ".KBBBBBBBBBBBBK.",
        ".KBBBBKKKKBBBBK.",
        "..KBBBBBBBBBBK..",
        "...KKKKKKKKKK...",
        "................",
    ])

    static let sleepy = PixelSprite([
        "................",
        "................",
        ".....KKKKKK.....",
        "...KKBBBBBBKK...",
        "..KBBBBBBBBBBK..",
        ".KBBBBBBBBBBBBK.",
        ".KBBBBBBBBBBBBK.",
        ".KBBKKBBBBKKBBK.",
        ".KBBBBBBBBBBBBK.",
        ".KBBBBBBBBBBBBK.",
        ".KBBBBBKKBBBBBK.",
        "..KBBBBBBBBBBK..",
        "...KKKKKKKKKK...",
        "................",
    ])

    static let sleepyZ = PixelSprite([
        "...........ZZZ..",
        "............Z...",
        ".....KKKKKKZZZ..",
        "...KKBBBBBBKK...",
        "..KBBBBBBBBBBK..",
        ".KBBBBBBBBBBBBK.",
        ".KBBBBBBBBBBBBK.",
        ".KBBKKBBBBKKBBK.",
        ".KBBBBBBBBBBBBK.",
        ".KBBBBBBBBBBBBK.",
        ".KBBBBBKKBBBBBK.",
        "..KBBBBBBBBBBK..",
        "...KKKKKKKKKK...",
        "................",
    ])

    static let sad = PixelSprite([
        "................",
        "................",
        ".....KKKKKK.....",
        "...KKBBBBBBKK...",
        "..KBBBBBBBBBBK..",
        ".KBBBBBBBBBBBBK.",
        ".KBBBKBBBBKBBBK.",
        ".KBBBKBBBBKBBBK.",
        ".KBTBBBBBBBBBBK.",
        ".KBBBBKKKKBBBBK.",
        ".KBBBKBBBBKBBBK.",
        "..KBBBBBBBBBBK..",
        "...KKKKKKKKKK...",
        "................",
    ])

    static let sadTearLow = PixelSprite([
        "................",
        "................",
        ".....KKKKKK.....",
        "...KKBBBBBBKK...",
        "..KBBBBBBBBBBK..",
        ".KBBBBBBBBBBBBK.",
        ".KBBBKBBBBKBBBK.",
        ".KBBBKBBBBKBBBK.",
        ".KBBBBBBBBBBBBK.",
        ".KBTBBKKKKBBBBK.",
        ".KBBBKBBBBKBBBK.",
        "..KBBBBBBBBBBK..",
        "...KKKKKKKKKK...",
        "................",
    ])
}

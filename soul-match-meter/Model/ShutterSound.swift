import AVFoundation

/// The shutter click on a locked reading: 70 ms of white noise with a cubic
/// decay through an 1800 Hz high-pass, at half gain. Rendered once into an
/// in-memory WAV; swap in a recorded file here when there is one.
enum ShutterSound {
    private static let player: AVAudioPlayer? = {
        // Mix with whatever is already playing, and stay quiet on silent.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        let player = try? AVAudioPlayer(data: render())
        player?.prepareToPlay()
        return player
    }()

    static func play() {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    private static func render() -> Data {
        let rate = 44_100
        let count = Int(Double(rate) * 0.07)

        // RBJ high-pass biquad at 1800 Hz. Web Audio reads a high-pass Q of 1
        // in dB, i.e. a linear Q of about 1.12.
        let w0 = 2 * Double.pi * 1800 / Double(rate)
        let alpha = sin(w0) / (2 * pow(10, 1.0 / 20))
        let cosW0 = cos(w0)
        let a0 = 1 + alpha
        let b0 = (1 + cosW0) / 2 / a0
        let b1 = -(1 + cosW0) / a0
        let a1 = -2 * cosW0 / a0
        let a2 = (1 - alpha) / a0

        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        var samples: [Int16] = []
        samples.reserveCapacity(count)
        for i in 0..<count {
            let x = Double.random(in: -1...1) * pow(1 - Double(i) / Double(count), 3)
            let y = b0 * x + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            samples.append(Int16(max(-1, min(1, y * 0.5)) * Double(Int16.max)))
        }

        // 16-bit mono PCM WAV.
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let bytes = count * 2
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1)) // PCM
        append(UInt16(1)) // mono
        append(UInt32(rate))
        append(UInt32(rate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(bytes))
        for sample in samples { append(sample) }
        return data
    }
}

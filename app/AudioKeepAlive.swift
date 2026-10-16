//  Glance: keeps your AirPods connected to the Mac.
//  When nothing is playing, macOS lets AirPods go idle (or hand over to your iPhone),
//  and their head tracking stops. Playing a sound far too quiet to hear keeps them awake.

import AVFoundation

@MainActor
final class AudioKeepAlive {
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?
    private(set) var running = false

    func start() {
        guard !running else { return }
        running = true
        build()
        // When the output changes (AirPods reconnect, speakers plugged in), restart on the new output
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                self.engine?.stop()
                self.build()
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine?.stop()
        engine = nil
    }

    /// Made outside the main actor: the audio system calls this on its own thread.
    nonisolated private static func makeSource() -> AVAudioSourceNode {
        // Tiny noise, about -100 dB: inaudible, but not pure digital silence, which can be ignored
        AVAudioSourceNode { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<Int(frameCount) { data[i] = Float.random(in: -0.00001...0.00001) }
            }
            return noErr
        }
    }

    private func build() {
        let e = AVAudioEngine()
        let format = e.outputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else { engine = nil; return }
        let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)
        let source = Self.makeSource()
        e.attach(source)
        e.connect(source, to: e.mainMixerNode, format: mono)
        do {
            try e.start()
            engine = e
        } catch {
            engine = nil
        }
    }
}

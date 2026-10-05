import XCTest
import AVFoundation
@testable import Narrateify

final class TimedSpeechTests: XCTestCase {
    func testRepeatedWordsUnicodeAndNegativeStart() {
        let text = "👋 Café, café!"
        let stamps = [
            KokoroTimestamp(word: "Café", start_time: -0.007, end_time: 0.4),
            KokoroTimestamp(word: ",", start_time: 0.4, end_time: 0.5),
            KokoroTimestamp(word: "café", start_time: 0.5, end_time: 0.9),
            KokoroTimestamp(word: "!", start_time: 0.9, end_time: 1.2)
        ]
        let mapped = SpeechTimeline.map(stamps, text: text, duration: 1)
        XCTAssertEqual(mapped.map(\.location), [3, 7, 9, 13])
        XCTAssertEqual(mapped.map { (text as NSString).substring(with: $0.range) }, ["Café", ",", "café", "!"])
        XCTAssertEqual(mapped.first?.start, 0)
        XCTAssertEqual(mapped.last?.end, 1)
    }

    func testUnmatchedAndInvalidTimestampsAreSkipped() {
        let stamps = [
            KokoroTimestamp(word: "missing", start_time: 0, end_time: 0.2),
            KokoroTimestamp(word: "Hello", start_time: .nan, end_time: 0.4),
            KokoroTimestamp(word: "Hello", start_time: 0.5, end_time: 0.4),
            KokoroTimestamp(word: "Hello", start_time: 0.5, end_time: 0.9)
        ]
        let mapped = SpeechTimeline.map(stamps, text: "Hello", duration: 1)
        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped.first?.start, 0.5)
    }

    func testChunkOffsetsAndSeekBoundaries() {
        let a = SpeechTimeline.map([KokoroTimestamp(word: "One", start_time: 0, end_time: 0.5)],
                                   text: "One. ", duration: 1)
        let b = SpeechTimeline.map([KokoroTimestamp(word: "Two", start_time: 0.1, end_time: 0.6)],
                                   text: "Two.", duration: 1, textOffset: 5, timeOffset: 1)
        let timeline = a + b
        XCTAssertNil(SpeechTimeline.active(at: -0.01, in: timeline))
        XCTAssertEqual(SpeechTimeline.active(at: 0, in: timeline)?.location, 0)
        XCTAssertNil(SpeechTimeline.active(at: 0.5, in: timeline))
        XCTAssertEqual(SpeechTimeline.active(at: 1.1, in: timeline)?.location, 5)
        XCTAssertNil(SpeechTimeline.active(at: 1.6, in: timeline))
        // Scrub backwards: selection depends solely on the actual audio clock.
        XCTAssertEqual(SpeechTimeline.active(at: 0.2, in: timeline)?.location, 0)
    }

    func testOldHistoryStillDecodesAndNewTimingsRoundTrip() throws {
        let original = NarrationRecord(id: UUID(), date: Date(), text: "One.", characterCount: 4,
            credits: 0, estimatedCost: 0, duration: 1, fileName: "test.wav", voiceId: "af_heart",
            voiceName: "af_heart", modelId: "kokoro", engine: "Kokoro (local)")
        let data = try JSONEncoder().encode(original)
        XCTAssertNil(try JSONDecoder().decode(NarrationRecord.self, from: data).wordTimings)
        var timed = original
        timed.wordTimings = [SpeechTiming(location: 0, length: 3, start: 0, end: 0.5)]
        XCTAssertEqual(try JSONDecoder().decode(NarrationRecord.self,
                       from: JSONEncoder().encode(timed)), timed)
    }

    @MainActor
    func testLocalServerURLValidation() {
        XCTAssertNotNil(KokoroServer.localURL(" http://127.0.0.1:8880 "))
        XCTAssertNotNil(KokoroServer.localURL("http://localhost:8880"))
        XCTAssertNil(KokoroServer.localURL("https://example.com"))
        XCTAssertNil(KokoroServer.localURL("file:///tmp/test"))
        XCTAssertNil(KokoroServer.localURL("http://localhost:8880?secret=123"))
    }

    @MainActor
    func testWAVMergeFinalizesHeaderAndIncludesBothChunks() throws {
        let a = try silence(seconds: 0.3)
        let b = try silence(seconds: 0.7)
        let merged = try AudioJoiner.mergeWAV([a, b])
        let player = try AVAudioPlayer(data: merged)
        XCTAssertEqual(player.duration, 1, accuracy: 0.001)
    }

    @MainActor
    func testPauseSeekAndChangingAudioResetTranscript() throws {
        let audio = AudioController()
        audio.load(data: try silence(seconds: 2), autoplay: false)
        let timings = [SpeechTiming(location: 0, length: 3, start: 0, end: 0.5),
                       SpeechTiming(location: 5, length: 3, start: 1, end: 1.5)]
        audio.setTranscript("One. Two.", timings: timings)
        let originalRate = audio.rate
        audio.rate = 1.5
        defer { audio.rate = originalRate }
        audio.seek(to: 1.2)
        XCTAssertFalse(audio.isPlaying)
        XCTAssertEqual(SpeechTimeline.active(at: audio.currentTime, in: audio.wordTimings)?.location, 5)
        audio.pause()
        XCTAssertEqual(audio.currentTime, 1.2, accuracy: 0.01)
        audio.seek(to: 0.1)
        XCTAssertEqual(SpeechTimeline.active(at: audio.currentTime, in: audio.wordTimings)?.location, 0)
        audio.load(data: try silence(seconds: 1), autoplay: false)
        XCTAssertTrue(audio.wordTimings.isEmpty)
        XCTAssertTrue(audio.readerSentences.isEmpty)
    }

    func testStreamingWAVPlaceholderSizesAreRepaired() throws {
        var wav = try silence(seconds: 0.5)
        let marker = wav.range(of: Data("data".utf8))!
        for i in 0..<4 {
            wav[4 + i] = 255
            wav[marker.lowerBound + 4 + i] = 255
        }
        let fixed = try KokoroClient.finalizeWAV(wav)
        XCTAssertEqual(fixed.duration, 0.5, accuracy: 0.001)
        XCTAssertNotEqual(Array(fixed.data[4..<8]), [255, 255, 255, 255])
        XCTAssertThrowsError(try KokoroClient.finalizeWAV(Data("not audio".utf8)))
        XCTAssertThrowsError(try KokoroClient.finalizeWAV(Data(wav.prefix(40))))
    }

    private func silence(seconds: Double) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        let frames = AVAudioFrameCount(seconds * 24000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        memset(buffer.floatChannelData![0], 0, Int(frames) * MemoryLayout<Float>.size)
        var file: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings)
        try file?.write(from: buffer)
        if #available(macOS 15, *) { file?.close() }
        file = nil
        return try Data(contentsOf: url)
    }
}

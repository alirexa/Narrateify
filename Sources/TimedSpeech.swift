import Foundation
import AVFoundation

/// UTF-16 text offsets match NSString, including emoji and non-ASCII text.
struct SpeechTiming: Codable, Hashable {
    let location: Int
    let length: Int
    let start: Double
    let end: Double
    var range: NSRange { NSRange(location: location, length: length) }
}

struct KokoroTimestamp: Decodable {
    let word: String
    let start_time: Double
    let end_time: Double
}

struct CaptionedAudio {
    let audio: Data
    let duration: Double
    let timestamps: [KokoroTimestamp]
}

enum SpeechTimeline {
    /// Match monotonically so repeated words never jump back to earlier text.
    /// Unmatched normalized words are skipped rather than assigned invented times.
    static func map(_ stamps: [KokoroTimestamp], text: String, duration: Double,
                    textOffset: Int = 0, timeOffset: Double = 0) -> [SpeechTiming] {
        let source = text as NSString
        var cursor = 0
        var previousEnd = 0.0
        var result: [SpeechTiming] = []
        for stamp in stamps {
            let word = stamp.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty, stamp.start_time.isFinite, stamp.end_time.isFinite,
                  stamp.end_time > stamp.start_time, cursor < source.length else { continue }
            let range = source.range(of: word, options: [.caseInsensitive, .diacriticInsensitive],
                                     range: NSRange(location: cursor, length: min(96, source.length - cursor)))
            guard range.location != NSNotFound else { continue }
            let start = min(duration, max(previousEnd, max(0, stamp.start_time)))
            let end = min(duration, max(start, stamp.end_time))
            cursor = NSMaxRange(range)
            guard end > start else { continue }
            result.append(SpeechTiming(location: range.location + textOffset, length: range.length,
                                       start: start + timeOffset, end: end + timeOffset))
            previousEnd = end
        }
        return result
    }

    static func active(at time: Double, in timings: [SpeechTiming]) -> SpeechTiming? {
        var lo = 0, hi = timings.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if timings[mid].start <= time { lo = mid + 1 } else { hi = mid }
        }
        guard lo > 0, time < timings[lo - 1].end else { return nil }
        return timings[lo - 1]
    }
}

extension KokoroClient {
    func synthesizeCaptioned(text: String) async throws -> CaptionedAudio {
        var request = URLRequest(url: baseURL.appendingPathComponent("dev/captioned_speech"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "kokoro", "input": text, "voice": voice, "speed": speed,
            "response_format": "wav", "stream": false, "return_timestamps": true,
            "return_download_link": false
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw KokoroError.empty }
        guard (200..<300).contains(http.statusCode) else {
            throw KokoroError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        struct Response: Decodable {
            let audio: String
            let audio_format: String
            let timestamps: [KokoroTimestamp]
        }
        let body = try JSONDecoder().decode(Response.self, from: data)
        guard ["wav", "audio/wav", "audio/x-wav"].contains(body.audio_format), let encoded = Data(base64Encoded: body.audio),
              !encoded.isEmpty else { throw KokoroError.empty }
        let wav = try Self.finalizeWAV(encoded)
        return CaptionedAudio(audio: wav.data, duration: wav.duration, timestamps: body.timestamps)
    }

    /// FFmpeg's streaming WAV responses have unknown RIFF/data lengths
    /// (0xffffffff). Replace them with the sizes of the completed response.
    /// This preserves exact PCM samples and avoids MP3 encoder delay.
    static func finalizeWAV(_ input: Data) throws -> (data: Data, duration: Double) {
        guard input.count >= 44, input.count < Int(UInt32.max),
              String(data: input[0..<4], encoding: .ascii) == "RIFF",
              String(data: input[8..<12], encoding: .ascii) == "WAVE" else {
            throw KokoroError.empty
        }
        func u32(_ offset: Int) -> Int {
            (0..<4).reduce(0) { $0 | (Int(input[offset + $1]) << (8 * $1)) }
        }
        func u16(_ offset: Int) -> Int { Int(input[offset]) | (Int(input[offset + 1]) << 8) }
        var position = 12
        var bytesPerSecond = 0
        var blockAlign = 0
        while position + 8 <= input.count {
            let name = String(data: input[position..<position + 4], encoding: .ascii)
            let size = u32(position + 4)
            let payload = position + 8
            if name == "fmt " {
                guard size >= 16, size <= input.count - payload,
                      [1, 3, 65534].contains(u16(payload)) else { throw KokoroError.empty }
                bytesPerSecond = u32(payload + 8)
                blockAlign = u16(payload + 12)
                guard blockAlign > 0, bytesPerSecond > 0,
                      u32(payload + 4) * blockAlign == bytesPerSecond else { throw KokoroError.empty }
            }
            if name == "data" {
                guard blockAlign > 0, bytesPerSecond > 0 else { throw KokoroError.empty }
                let available = input.count - payload
                let count = size == Int(UInt32.max) ? available : size
                guard count > 0, count <= available, count % blockAlign == 0 else { throw KokoroError.empty }
                var data = input
                func writeSize(_ value: Int, at offset: Int) {
                    for i in 0..<4 { data[offset + i] = UInt8((value >> (i * 8)) & 255) }
                }
                writeSize(input.count - 8, at: 4)
                writeSize(count, at: position + 4)
                return (data, Double(count) / Double(bytesPerSecond))
            }
            guard size <= input.count - payload else { throw KokoroError.empty }
            position = payload + size + size % 2
        }
        throw KokoroError.empty
    }
}

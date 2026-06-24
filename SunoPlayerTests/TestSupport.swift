import Foundation
@testable import SunoPlayer

enum TestSupport {
    /// Builds a Track with a deterministic file name; id is unique per call.
    static func track(
        title: String,
        artist: String? = nil,
        fileName: String? = nil,
        duration: TimeInterval = 10,
        dateImported: Date = Date()
    ) -> Track {
        Track(
            title: title,
            artist: artist,
            fileName: fileName ?? "\(title).m4a",
            duration: duration,
            dateImported: dateImported
        )
    }

    /// A minimal, valid PCM WAV (silence) that AVPlayer can actually play. Used to exercise
    /// real playback state without bundling a media asset.
    static func silentWAV(seconds: Double = 0.4, sampleRate: Int = 8000) -> Data {
        let bytesPerSample = 2
        let numSamples = Int(seconds * Double(sampleRate))
        let dataSize = numSamples * bytesPerSample
        var d = Data()
        func str(_ s: String) { d.append(s.data(using: .ascii)!) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        str("RIFF"); u32(UInt32(36 + dataSize)); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * bytesPerSample)); u16(UInt16(bytesPerSample)); u16(16)
        str("data"); u32(UInt32(dataSize))
        d.append(Data(count: dataSize))
        return d
    }

    /// Writes data into the app documents directory under `fileName` and returns a Track for it.
    @discardableResult
    static func writeTrack(named fileName: String, data: Data, title: String, duration: TimeInterval = 0.4) throws -> Track {
        let url = Track.documentsDirectory.appendingPathComponent(fileName)
        try data.write(to: url)
        return Track(title: title, fileName: fileName, duration: duration)
    }

    static func removeFile(_ track: Track) {
        try? FileManager.default.removeItem(at: track.fileURL)
    }
}

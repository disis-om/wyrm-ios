import CryptoKit
import Foundation

enum EngineAssetBundle {
    enum AssetError: LocalizedError {
        case missing(String)
        case invalidManifest
        case digestMismatch(String)

        var errorDescription: String? {
            switch self {
            case .missing(let path): return "Engine asset missing: \(path)"
            case .invalidManifest: return "Engine asset manifest is invalid"
            case .digestMismatch(let path): return "Engine asset checksum mismatch: \(path)"
            }
        }
    }

    static func verify() throws -> Int {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("EngineAssets", isDirectory: true),
              let manifest = try? String(contentsOf: root.appendingPathComponent("SHA256SUMS"), encoding: .utf8) else {
            throw AssetError.missing("EngineAssets/SHA256SUMS")
        }

        let lines = manifest.split(whereSeparator: \.isNewline)
        guard lines.count == 17 else { throw AssetError.invalidManifest }

        for line in lines {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2,
                  fields[0].count == 64,
                  fields[0].allSatisfy({ $0.isHexDigit }),
                  !fields[1].hasPrefix("/"),
                  !fields[1].split(separator: "/").contains("..") else {
                throw AssetError.invalidManifest
            }

            let path = String(fields[1])
            let url = root.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: url) else { throw AssetError.missing(path) }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == String(fields[0]) else { throw AssetError.digestMismatch(path) }
        }
        return lines.count
    }
}

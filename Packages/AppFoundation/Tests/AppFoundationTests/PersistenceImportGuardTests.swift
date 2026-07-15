import Foundation
import Testing

/// Yasak-import lint kuralının SAF, test edilebilir çekirdeği (SS-002 kalıbı, 03 §9). Karar
/// mantığı iki ayrık yordama indirgenmiştir ki hem gerçek kaynak ağacında hem de sentetik
/// kenar durumlarında (kaçan import biçimleri, kardeş dizinler) doğrulanabilsin (bulgu #12).
enum SwiftDataImportRule {
    /// Bir kaynak satırının SwiftData modülünü import edip etmediği. TÜM biçimleri yakalar:
    /// `import SwiftData`, `@_exported`/`@preconcurrency`/`@_implementationOnly` (ve kombinasyon)
    /// öntakılı biçimler, ve `import struct SwiftData.Schema` gibi altmodül (submodule) import'ları.
    static func importsSwiftData(inLine rawLine: String) -> Bool {
        // Satır içi yorumu at, token'lara böl.
        var line = rawLine
        if let commentRange = line.range(of: "//") {
            line = String(line[..<commentRange.lowerBound])
        }
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let importIndex = tokens.firstIndex(of: "import") else { return false }
        // `import`'tan önceki her token bir attribute olmalı (`@...`) — "print(import)" gibi
        // sahte eşleşmeleri ele; öntakı yoksa (importIndex == 0) de geçerli.
        guard tokens[..<importIndex].allSatisfy({ $0.hasPrefix("@") }) else { return false }
        var rest = Array(tokens[(importIndex + 1)...])
        // Opsiyonel import-kind (`import struct SwiftData.Schema`).
        let importKinds = ["struct", "class", "enum", "protocol", "typealias", "func", "let", "var", "actor"]
        if let first = rest.first, importKinds.contains(first) {
            rest.removeFirst()
        }
        guard let path = rest.first else { return false }
        // Modül = yolun ilk bileşeni (`SwiftData.Schema` → `SwiftData`).
        let module = path.split(separator: ".").first.map(String.init) ?? path
        return module == "SwiftData"
    }

    /// Dosyanın Persistence kökü ALTINDA (veya tam köküyle) olup olmadığı. Yol karşılaştırması
    /// ayırıcıya duyarlıdır: `.../Persistence` öneki `.../PersistenceSupport` KARDEŞİNİ yanlışça
    /// izinli saymaz (bulgu #12b).
    static func isAllowed(filePath: String, underPersistenceRoot root: String) -> Bool {
        filePath == root || filePath.hasPrefix(root + "/")
    }
}

/// `import SwiftData` YALNIZ `Sources/AppFoundation/Storage/Persistence/` altında geçebilir
/// (03 §9). Persistence vendor'ının tek klasöre hapsedildiğini derleme dışı, grep-tabanlı bir
/// denetimle bağlayıcı kılar.
struct PersistenceImportGuardTests {
    private func persistenceRoot() -> (sources: URL, persistence: URL) {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AppFoundationTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // AppFoundation (paket kökü)
        let sourcesRoot = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("AppFoundation")
        let persistence = sourcesRoot
            .appendingPathComponent("Storage")
            .appendingPathComponent("Persistence")
        return (sourcesRoot, persistence)
    }

    @Test func swiftDataImportedOnlyUnderPersistence() throws {
        let roots = persistenceRoot()
        let persistencePath = roots.persistence.standardizedFileURL.path

        let fileManager = FileManager.default
        let enumerator = try #require(
            fileManager.enumerator(at: roots.sources, includingPropertiesForKeys: nil),
            "AppFoundation kaynak dizini bulunamadı: \(roots.sources.path)"
        )

        var offenders: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let importsSwiftData = contents
                .split(whereSeparator: \.isNewline)
                .contains { SwiftDataImportRule.importsSwiftData(inLine: String($0)) }
            guard importsSwiftData else { continue }
            let standardized = fileURL.standardizedFileURL.path
            if !SwiftDataImportRule.isAllowed(filePath: standardized, underPersistenceRoot: persistencePath) {
                offenders.append(fileURL.lastPathComponent)
            }
        }

        #expect(
            offenders.isEmpty,
            "import SwiftData yalnız Storage/Persistence/ altında olmalı (03 §9); ihlal: \(offenders)"
        )
    }

    /// Bulgu #12a: matcher `import struct SwiftData.X`, `@_implementationOnly`, kombinasyon
    /// öntakılar dâhil TÜM SwiftData import biçimlerini yakalamalı; SwiftData OLMAYAN import'ları
    /// (yanlış pozitif) yakalamamalı.
    @Test func matcherCatchesAllSwiftDataImportForms() {
        let matches = [
            "import SwiftData",
            "  import SwiftData",
            "import SwiftData // yorum",
            "@_exported import SwiftData",
            "@preconcurrency import SwiftData",
            "@_implementationOnly import SwiftData",
            "@preconcurrency @_exported import SwiftData",
            "import struct SwiftData.Schema",
            "import class SwiftData.ModelContext",
            "@_implementationOnly import struct SwiftData.ModelContainer"
        ]
        for line in matches {
            #expect(SwiftDataImportRule.importsSwiftData(inLine: line), "yakalanmalıydı: \(line)")
        }

        let nonMatches = [
            "import Foundation",
            "import SwiftDataHelpers",
            "import struct Foundation.Data",
            "// import SwiftData",
            "let x = swiftDataImport()"
        ]
        for line in nonMatches {
            #expect(!SwiftDataImportRule.importsSwiftData(inLine: line), "yakalanmamalıydı: \(line)")
        }
    }

    /// Bulgu #12b: `.../Persistence` kökü, `.../PersistenceSupport` KARDEŞ dizinini izinli
    /// saymamalı (ayırıcıya duyarlı önek). Gerçek alt yollar ise izinli olmalı.
    @Test func siblingDirectoryIsNotTreatedAsUnderPersistence() {
        let root = "/repo/Sources/AppFoundation/Storage/Persistence"
        #expect(SwiftDataImportRule.isAllowed(
            filePath: "/repo/Sources/AppFoundation/Storage/Persistence/WatchHistoryStore.swift",
            underPersistenceRoot: root
        ))
        #expect(!SwiftDataImportRule.isAllowed(
            filePath: "/repo/Sources/AppFoundation/Storage/PersistenceSupport/Leak.swift",
            underPersistenceRoot: root
        ))
    }
}

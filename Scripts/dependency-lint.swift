#!/usr/bin/env swift
// dependency-lint — 03-mimari.md §4 bağımlılık kurallarını (R1–R7) CI'da bağlayıcı kılar.
// Regex ile manifest parse etmez; her paket için `swift package dump-package` çıktısındaki
// JSON'dan yerel (fileSystem) ve uzak (sourceControl/registry) bağımlılıkları okur ve
// izin matrisiyle karşılaştırır. Kullanım: repo kökünden `swift Scripts/dependency-lint.swift`.

import Foundation

// MARK: - İzin matrisi (03 §4 mermaid grafiğine birebir; plan §3.1)

let allowed: [String: Set<String>] = [
    "AppFoundation": [],
    "DesignSystem": [],
    "ContentKit": ["AppFoundation"],
    "AnalyticsKit": ["AppFoundation"],
    "PlayerKit": ["AppFoundation", "DesignSystem", "ContentKit", "AnalyticsKit"],
    "DiscoverKit": ["AppFoundation", "DesignSystem", "ContentKit", "AnalyticsKit"],
    "LibraryKit": ["AppFoundation", "DesignSystem", "ContentKit", "AnalyticsKit"],
    "WalletKit": ["AppFoundation", "DesignSystem", "AnalyticsKit"],
    "RewardsKit": ["AppFoundation", "DesignSystem", "AnalyticsKit"],
    "ProfileKit": ["AppFoundation", "DesignSystem", "AnalyticsKit"],
]

/// R6: üçüncü parti (sourceControl) bağımlılık allowlist'i — F0'da BOŞ.
/// F1+: AnalyticsKit→firebase-ios-sdk, RewardsKit→google-mobile-ads,
/// DesignSystem→swift-snapshot-testing (yalnız test).
let thirdPartyAllowlist: [String: Set<String>] = [:]

/// Topolojik rapor sırası (build sırasıyla aynı).
let packageOrder = [
    "AppFoundation", "DesignSystem", "ContentKit", "AnalyticsKit",
    "PlayerKit", "DiscoverKit", "LibraryKit", "WalletKit", "RewardsKit", "ProfileKit",
]

let baseLayer: Set<String> = ["AppFoundation", "DesignSystem"]
let featurePackages: Set<String> = [
    "PlayerKit", "DiscoverKit", "LibraryKit", "WalletKit", "RewardsKit", "ProfileKit",
]

/// İhlal mesajındaki kural numarasını 03 §4 tablosuna göre seçer.
func rule(package: String, dependency: String) -> String {
    if baseLayer.contains(package) { return "R1" }
    if package == "AnalyticsKit" { return "R4" }
    if package == "ContentKit" { return "R3" }
    if featurePackages.contains(package), featurePackages.contains(dependency) { return "R2" }
    if dependency == "ContentKit" { return "R3" }
    return "R2"
}

// MARK: - dump-package çağrısı ve JSON okuma

struct LintError: Error, CustomStringConvertible {
    let description: String
}

func repoRoot() -> URL {
    let fm = FileManager.default
    var candidates = [URL(fileURLWithPath: fm.currentDirectoryPath)]
    // `swift Scripts/dependency-lint.swift` dışında bir cwd'den koşulursa script konumundan türet.
    let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0],
                        relativeTo: candidates[0]).standardizedFileURL
    candidates.append(scriptURL.deletingLastPathComponent().deletingLastPathComponent())
    for root in candidates {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: root.appendingPathComponent("Packages").path,
                         isDirectory: &isDir), isDir.boolValue {
            return root
        }
    }
    FileHandle.standardError.write(Data("HATA: Packages/ dizini bulunamadı — repo kökünden çalıştırın.\n".utf8))
    exit(1)
}

func dumpPackage(name: String, root: URL) throws -> [String: Any] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "package", "dump-package",
                         "--package-path", "Packages/\(name)"]
    process.currentDirectoryURL = root
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(data: errData, encoding: .utf8) ?? ""
        throw LintError(description: "dump-package başarısız (\(name)): \(message)")
    }
    guard let json = try JSONSerialization.jsonObject(with: outData) as? [String: Any] else {
        throw LintError(description: "dump-package çıktısı JSON nesnesi değil (\(name))")
    }
    return json
}

struct Dependencies {
    var local: [String] = []   // Packages/ altındaki paket adları
    var remote: [String] = []  // sourceControl/registry identity'leri
}

func extractDependencies(from manifest: [String: Any], package: String) throws -> Dependencies {
    var result = Dependencies()
    let entries = manifest["dependencies"] as? [[String: Any]] ?? []
    for entry in entries {
        if let fileSystem = entry["fileSystem"] as? [[String: Any]] {
            for item in fileSystem {
                guard let path = item["path"] as? String else {
                    throw LintError(description: "fileSystem bağımlılığında path alanı yok (\(package))")
                }
                result.local.append(URL(fileURLWithPath: path).lastPathComponent)
            }
        } else if let sourceControl = entry["sourceControl"] as? [[String: Any]] {
            for item in sourceControl {
                result.remote.append(item["identity"] as? String ?? "<bilinmeyen-uzak>")
            }
        } else if let registry = entry["registry"] as? [[String: Any]] {
            for item in registry {
                result.remote.append(item["identity"] as? String ?? "<bilinmeyen-registry>")
            }
        } else {
            throw LintError(description: "Tanınmayan bağımlılık biçimi (\(package)): \(entry.keys.sorted())")
        }
    }
    return result
}

// MARK: - Denetim

let root = repoRoot()
var violations: [String] = []
var summaryLines: [String] = []

for package in packageOrder {
    let manifest: [String: Any]
    let deps: Dependencies
    do {
        manifest = try dumpPackage(name: package, root: root)
        deps = try extractDependencies(from: manifest, package: package)
    } catch {
        FileHandle.standardError.write(Data("HATA: \(error)\n".utf8))
        exit(1)
    }

    let allowedSet = allowed[package] ?? []
    for dep in deps.local where !allowedSet.contains(dep) {
        violations.append("İHLAL: \(package) -> \(dep) (\(rule(package: package, dependency: dep)))")
    }
    for dep in deps.remote where !(thirdPartyAllowlist[package]?.contains(dep) ?? false) {
        violations.append("İHLAL: \(package) -> \(dep) (R6)")
    }

    let described = deps.local.isEmpty && deps.remote.isEmpty
        ? "—"
        : (deps.local + deps.remote).joined(separator: ", ")
    summaryLines.append("  \(package) -> \(described)")
}

if violations.isEmpty {
    print("dependency-lint: \(packageOrder.count) paket R1–R7 matrisiyle uyumlu; üçüncü parti bağımlılık yok.")
    summaryLines.forEach { print($0) }
    exit(0)
} else {
    violations.forEach { print($0) }
    exit(1)
}

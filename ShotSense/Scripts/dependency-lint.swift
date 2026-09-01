#!/usr/bin/env swift
//
// ShotSense bağımlılık denetçisi — 03-mimari.md §4 (R1–R7) ve KANON §1/§2'yi zorlar.
//
// Derleyici bu kuralları göremez: bir paketin "yanlış" çerçeveyi import etmesi teknik olarak
// geçerli Swift'tir. Kurallar mimarinin kendisidir, bu yüzden CI'da metin düzeyinde denetlenir.
//
// Kullanım:  swift Scripts/dependency-lint.swift   (repo kökünden)
// Çıkış kodu 1 = ihlal var.

import Foundation

// MARK: - Kural tanımı

struct Rule {
    let id: String
    let description: String
    /// Kuralın uygulandığı paket adları; boş = tüm paketler + App.
    let packages: Set<String>
    /// Yasak import modül adları.
    let forbiddenImports: Set<String>
    /// Yasak sembol/desenler (import dışı, ör. `URLSession`).
    let forbiddenSymbols: Set<String>
}

let appleServiceFrameworks: Set<String> = [
    "Vision", "FoundationModels", "Photos", "PhotosUI", "EventKit", "EventKitUI",
    "StoreKit", "Contacts", "ContactsUI", "SwiftData", "CoreSpotlight", "BackgroundTasks",
    "SwiftUI", "UIKit", "NaturalLanguage",
]

let adapterPackages: Set<String> = [
    "OCRKit", "IntelligenceKit", "IngestKit", "IndexKit", "ActionKit", "PaywallKit",
]

let rules: [Rule] = [
    Rule(
        id: "R1",
        description: "ShotCore yalnız Foundation + AppFoundation import eder (domain saftır).",
        packages: ["ShotCore"],
        forbiddenImports: appleServiceFrameworks,
        forbiddenSymbols: []
    ),
    Rule(
        id: "R2",
        description: "Adaptör paketleri birbirini import edemez.",
        packages: adapterPackages,
        forbiddenImports: adapterPackages,
        forbiddenSymbols: []
    ),
    Rule(
        id: "R3",
        description: "LibraryKit adaptör paketi import edemez; yalnız ShotCore portlarını kullanır.",
        packages: ["LibraryKit"],
        forbiddenImports: adapterPackages.union([
            "Vision", "FoundationModels", "Photos", "EventKit", "StoreKit", "SwiftData",
        ]),
        forbiddenSymbols: []
    ),
    Rule(
        id: "R5",
        description: "DesignSystem iş kuralı ve adaptör bilmez.",
        packages: ["DesignSystem"],
        forbiddenImports: adapterPackages,
        forbiddenSymbols: []
    ),
    Rule(
        id: "R7",
        description: "KANON §1 — ShotSense ağ isteği yapmaz.",
        packages: [],
        forbiddenImports: ["Network", "CFNetwork"],
        forbiddenSymbols: ["URLSession", "NWConnection", "CFSocket", "NSURLConnection"]
    ),
]

// MARK: - Tarama

struct Violation {
    let ruleID: String
    let file: String
    let line: Int
    let detail: String
}

let fileManager = FileManager.default
let root = fileManager.currentDirectoryPath

/// Denetlenecek kaynak kökleri. Test hedefleri hariç tutulur: testler sahte adaptör
/// kurabilmek için daha geniş import haklarına sahiptir.
let scanRoots = ["Packages", "App"]

func swiftFiles(under directory: String) -> [String] {
    guard let enumerator = fileManager.enumerator(atPath: directory) else { return [] }
    var results: [String] = []
    for case let path as String in enumerator where path.hasSuffix(".swift") {
        let full = directory + "/" + path
        // Test hedefleri ve derleme çıktıları denetim dışı.
        if full.contains("/Tests/") || full.contains("/.build/") { continue }
        results.append(full)
    }
    return results
}

/// Dosyanın hangi pakete ait olduğunu yoldan çıkarır: Packages/<Ad>/Sources/...
func packageName(for path: String) -> String {
    let components = path.split(separator: "/").map(String.init)
    if let index = components.firstIndex(of: "Packages"), components.count > index + 1 {
        return components[index + 1]
    }
    return "App"
}

func importedModule(in line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("import ") || trimmed.hasPrefix("@testable import ") else { return nil }
    let parts = trimmed.split(separator: " ")
    guard let last = parts.last else { return nil }
    // `import struct Foundation.Data` biçimini de kapsa.
    return last.split(separator: ".").first.map(String.init)
}

var violations: [Violation] = []

for scanRoot in scanRoots {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: scanRoot, isDirectory: &isDirectory), isDirectory.boolValue
    else { continue }

    for file in swiftFiles(under: scanRoot) {
        guard let contents = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
        let package = packageName(for: file)

        for (index, line) in contents.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            let code = line.split(separator: "/").first.map(String.init) ?? line
            guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }

            for rule in rules {
                let applies = rule.packages.isEmpty || rule.packages.contains(package)
                guard applies else { continue }

                if let module = importedModule(in: line), rule.forbiddenImports.contains(module) {
                    violations.append(
                        Violation(
                            ruleID: rule.id, file: file, line: lineNumber,
                            detail: "\(package) → `import \(module)` yasak. \(rule.description)"
                        )
                    )
                }
                for symbol in rule.forbiddenSymbols where code.contains(symbol) {
                    violations.append(
                        Violation(
                            ruleID: rule.id, file: file, line: lineNumber,
                            detail: "`\(symbol)` kullanımı yasak. \(rule.description)"
                        )
                    )
                }
            }
        }
    }
}

// MARK: - Rapor

if violations.isEmpty {
    print("✅ dependency-lint: \(rules.count) kural, ihlal yok. (kök: \(root))")
    exit(0)
}

print("❌ dependency-lint: \(violations.count) ihlal\n")
for violation in violations.sorted(by: { $0.file < $1.file }) {
    print("\(violation.file):\(violation.line): error: [\(violation.ruleID)] \(violation.detail)")
}
print("\nKurallar: docs/03-mimari.md §4 · docs/KANON.md")
exit(1)

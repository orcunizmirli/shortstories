import Foundation

/// Cihaz bütünlüğü (jailbreak/tamper) **danışma sinyali** (SS-100, F2). BEST-EFFORT: hiçbir
/// heuristik kesin değildir ve kolayca bypass edilebilir (jailbreak gizleme araçları, hook'lar).
/// Bu yüzden istemci ASLA karar vermez — sinyal cüzdan/kazanç isteklerine header olarak eklenir ve
/// KARAR BACKEND'dedir (05 §1 kural 2 "server otoritatiftir"; 09 SS-100). `reasons` yalnız gözlem/
/// hata ayıklama içindir; PII değildir ama fingerprinting yüzeyini daraltmak için header'a KONMAZ —
/// wire'a yalnız kaba `suspected` bayrağı gider (bkz. `FraudSignalHeaders`).
public struct DeviceIntegritySignal: Sendable, Equatable {
    /// Bütünlük şüphesini tetikleyen kaba neden kategorileri (istemci-içi gözlem; header'a girmez).
    public enum Reason: String, Sendable, Equatable, CaseIterable {
        /// Bilinen jailbreak artefaktı bir dosya/yol mevcut (ör. Cydia.app, MobileSubstrate).
        case suspiciousFile
        /// Bilinen jailbreak URL şeması açılabilir (ör. `cydia://`) — `canOpenURL` heuristiği.
        case suspiciousURLScheme
        /// Uygulama sandbox'ı DIŞINA yazma başarılı oldu (sağlıklı cihazda imkânsız).
        case sandboxEscape
    }

    /// Tetiklenen nedenler; boşsa cihaz temiz görünüyor (yine de KESİN değil — best-effort).
    public let reasons: [Reason]

    public init(reasons: [Reason]) {
        self.reasons = reasons
    }

    /// Herhangi bir heuristik tetiklendi mi? Wire bayrağı bundan türetilir (advisory, backend karar verir).
    public var suspected: Bool {
        !reasons.isEmpty
    }

    /// Hiçbir tamper heuristiği tetiklenmemiş sinyal.
    public static let clean = DeviceIntegritySignal(reasons: [])
}

/// Cihaz bütünlüğü PROB portu (SS-100). ENJEKTE edilebilir: testler gerçek OS/jailbreak API'sini
/// çağırmaz, sahte prob canlı bir sinyal döner. Canlı uygulama `BasicDeviceIntegrityProbe`'tur;
/// kompozisyon kökü (App) prob'u kurar, sonuç `FraudSignalInterceptor`'a taşınır.
public protocol DeviceIntegrityProbing: Sendable {
    /// Best-effort tamper heuristiklerini çalıştırıp danışma sinyali döner. Yan etkisiz olmalıdır
    /// (sandbox-dışı yazma denemesi yaparsa kendi geçici dosyasını temizler).
    func evaluate() -> DeviceIntegritySignal
}

/// STANDART/TEMEL jailbreak/tamper heuristikleri (SS-100). Her heuristik BEST-EFFORT'tur ve
/// bilinçli olarak bypass edilebilir; amaç düşük maliyetli, gürültülü bir danışma sinyali üretmek —
/// KESİN teşhis DEĞİL. Backend bu bayrağı kendi sunucu-taraflı sinyalleriyle (cihaz kimliği geçmişi,
/// kazanç hızı, receipt tutarlılığı) birleştirip karar verir.
///
/// Tüm OS-dokunuşları (dosya varlığı, URL şeması, sandbox-dışı yazma) `@Sendable` closure seam'leri
/// olarak ENJEKTE edilir → testler gerçek dosya sistemine/`UIApplication`'a dokunmadan her kombinasyonu
/// deterministik kurar. Varsayılanlar UIKit GEREKTİRMEZ (AppFoundation UIKit-free kalır): `canOpenScheme`
/// varsayılanı `false` döner — gerçek `UIApplication.canOpenURL(cydia://)` çağrısı (UIKit + `@MainActor`
/// + Info.plist `LSApplicationQueriesSchemes`) kompozisyon kökünde enjekte edilir.
public struct BasicDeviceIntegrityProbe: DeviceIntegrityProbing {
    private let suspiciousPaths: [String]
    private let suspiciousSchemes: [String]
    private let pathExists: @Sendable (String) -> Bool
    private let canOpenScheme: @Sendable (String) -> Bool
    private let sandboxEscapeProbe: @Sendable () -> Bool

    public init(
        suspiciousPaths: [String] = BasicDeviceIntegrityProbe.defaultSuspiciousPaths,
        suspiciousSchemes: [String] = BasicDeviceIntegrityProbe.defaultSuspiciousSchemes,
        pathExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        canOpenScheme: @escaping @Sendable (String) -> Bool = { _ in false },
        sandboxEscapeProbe: @escaping @Sendable () -> Bool = BasicDeviceIntegrityProbe.defaultSandboxEscapeProbe
    ) {
        self.suspiciousPaths = suspiciousPaths
        self.suspiciousSchemes = suspiciousSchemes
        self.pathExists = pathExists
        self.canOpenScheme = canOpenScheme
        self.sandboxEscapeProbe = sandboxEscapeProbe
    }

    public func evaluate() -> DeviceIntegritySignal {
        // Sabit sıra (deterministik test): dosya → URL şeması → sandbox kaçışı.
        var reasons: [DeviceIntegritySignal.Reason] = []
        if suspiciousPaths.contains(where: pathExists) {
            reasons.append(.suspiciousFile)
        }
        if suspiciousSchemes.contains(where: canOpenScheme) {
            reasons.append(.suspiciousURLScheme)
        }
        if sandboxEscapeProbe() {
            reasons.append(.sandboxEscape)
        }
        return DeviceIntegritySignal(reasons: reasons)
    }

    // MARK: - Varsayılan heuristik verileri (best-effort; tam liste değil, bypass edilebilir)

    /// Bilinen jailbreak araç/paket artefaktları. Kapsamlı DEĞİLDİR ve gizlenebilir — advisory.
    public static let defaultSuspiciousPaths: [String] = [
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Applications/Zebra.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/usr/sbin/sshd",
        "/usr/bin/ssh",
        "/bin/bash",
        "/etc/apt",
        "/private/var/lib/apt/"
    ]

    /// Bilinen jailbreak paket yöneticisi URL şemaları (canOpenURL heuristiği için).
    public static let defaultSuspiciousSchemes: [String] = [
        "cydia",
        "sileo",
        "zbra",
        "filza"
    ]

    /// Sandbox DIŞINA yazma denemesi: sağlıklı bir cihazda `/private/...` yazılabilir DEĞİLDİR;
    /// başarı jailbreak sinyalidir. Kendi geçici dosyasını temizler (yan etkisiz).
    public static let defaultSandboxEscapeProbe: @Sendable () -> Bool = {
        let path = "/private/" + UUID().uuidString + ".ss-integrity"
        do {
            try "x".write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }
}

import AppFoundation
import Foundation

// SS-141 — Rich push SAF çekirdeği. Bu dosya İKİ target'a derlenir: `ShortSeriesApp` (AppTests burada
// izole test eder) ve `NotificationServiceExtension` (NSE runtime'ında kullanır). Amaç: NSE runtime'ı
// (gerçek APNs/`UNNotification`) olmadan test edilebilir, deterministik karar mantığı. TASARIM KURALI:
// ham `UNNotification*` tipi BU katmana sızmaz — girdi yalnız APNs `userInfo` sözlüğü ([AnyHashable: Any])
// ve saf değer tipleridir; UN tiplerine çeviri (attachment/kategori/aksiyon) çağıran katmanda yapılır.

// MARK: - Kategori / aksiyon kimlikleri (NSE + AppDelegate ORTAK kaynağı)

/// Rich push kategori + aksiyon tanımları. NSE, kampanya tipinden türettiği kimliği
/// `content.categoryIdentifier`e yazar; `AppDelegate` AYNI kimliklerle `UNNotificationCategory` kaydeder
/// (aksiyon butonları eşleşsin). Kimlikler push kampanya tipiyle 1:1'dir (07 §5.2 "İçerik" kategorisi;
/// SS-141 aksiyonları: yeni bölüm → "İzle", kaldığın yerden devam → "Devam Et").
enum RichPushCategory {
    /// Yeni bölüm bildirimi kategorisi ("İzle" aksiyonu).
    static let newEpisodeIdentifier = "ss_new_episode"
    /// Kaldığın yerden devam bildirimi kategorisi ("Devam Et" aksiyonu).
    static let continueIdentifier = "ss_continue"

    /// Aksiyon butonu tanımı — UN tipsiz saf değer. `AppDelegate` bunu `UNNotificationAction`'a çevirir.
    struct Action: Equatable {
        let identifier: String
        let title: String
        /// Dokununca uygulamayı öne getir (deep link işlenebilsin) → `UNNotificationActionOptions.foreground`.
        let opensApp: Bool
    }

    /// Kategori tanımı — UN tipsiz saf değer. `AppDelegate` bunu `UNNotificationCategory`'ye çevirir.
    struct Descriptor: Equatable {
        let identifier: String
        let actions: [Action]
    }

    /// `AppDelegate`in açılışta kaydedeceği tüm rich push kategorileri (F1 kapsamı: yeni bölüm + devam-et).
    static let all: [Descriptor] = [
        Descriptor(
            identifier: newEpisodeIdentifier,
            actions: [Action(identifier: "ss_watch", title: "İzle", opensApp: true)]
        ),
        Descriptor(
            identifier: continueIdentifier,
            actions: [Action(identifier: "ss_resume", title: "Devam Et", opensApp: true)]
        )
    ]

    /// Kampanya tipini kategori kimliğine eşler (NSE `content.categoryIdentifier` için).
    static func identifier(for type: PushCampaignType) -> String {
        switch type {
        case .newEpisode: newEpisodeIdentifier
        case .continueWatching: continueIdentifier
        }
    }
}

// MARK: - Rich push sunum kararı (görsel URL + kategori)

/// APNs `userInfo`'dan çıkarılan rich-push sunum kararı: hangi görsel indirilecek ve hangi kategori
/// (aksiyon butonları) uygulanacak. İkisi de OPSİYONELDİR ve BAĞIMSIZDIR — biri yoksa diğeri yine uygulanır;
/// hiçbiri push'u DÜŞÜRMEZ (NSE en azından metni teslim eder). Parse tolerantır: iki dokümantasyon
/// arasındaki anahtar drift'i (07 §6.1 `imageURL` vs. uygulama snake_case'i) köprülenir.
struct RichPushPresentation: Equatable {
    /// İndirilecek görsel URL'i (geçerli http(s) değilse `nil` → metin-only teslim).
    let imageURL: URL?
    /// Uygulanacak kategori kimliği (kampanya tipi çözülemezse `nil` → varsayılan sunum).
    let categoryIdentifier: String?

    init(userInfo: [AnyHashable: Any]) {
        imageURL = Self.imageURL(from: userInfo)
        categoryIdentifier = Self.categoryIdentifier(from: userInfo)
    }

    /// Değer testleri için doğrudan kurucu.
    init(imageURL: URL?, categoryIdentifier: String?) {
        self.imageURL = imageURL
        self.categoryIdentifier = categoryIdentifier
    }

    /// Görsel URL anahtar adayları — sözleşme drift'ine karşı sıralı denenir (07 §6.1 `imageURL` birincil).
    private static let imageKeys = ["imageURL", "image_url", "image"]

    /// İlk geçerli http(s) görsel URL'ini döndürür; hiçbiri geçerli değilse `nil`.
    static func imageURL(from userInfo: [AnyHashable: Any]) -> URL? {
        for key in imageKeys {
            if let raw = userInfo[key] as? String, let url = validatedImageURL(raw) {
                return url
            }
        }
        return nil
    }

    /// Kategori kimliği: mevcut (test edilmiş) `PushPayload` tip-çözümünü YENİDEN KULLANIR — payload
    /// çözülemezse (F1 dışı/eksik rota) `nil`.
    static func categoryIdentifier(from userInfo: [AnyHashable: Any]) -> String? {
        guard let payload = PushPayload(userInfo: userInfo) else { return nil }
        return RichPushCategory.identifier(for: payload.type)
    }

    /// Yalnız mutlak http(s) URL'i kabul eder (host zorunlu). `file:`/`data:` ve şemasız girdiler reddedilir
    /// (NSE keyfi şema "indirmez"; güvenlik + geçerlilik).
    static func validatedImageURL(_ string: String) -> URL? {
        guard !string.isEmpty,
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}

// MARK: - Attachment dosya-uzantısı / MIME kararı

/// İndirilen görselin `UNNotificationAttachment`'a hangi dosya uzantısıyla/tipiyle bağlanacağını belirler.
/// iOS attachment tipini dosya UZANTISINDAN çıkarır; indirilen geçici dosyanın uzantısı yoktur, bu yüzden
/// URL yolundan veya yanıt MIME'ından deterministik bir uzantı türetilir. Ayrıca yanıtın gerçekten bir
/// görsel olup olmadığına karar verir (HTML hata sayfası vb. eklenmez).
enum RichPushAttachment {
    /// `UNNotificationAttachment` kimliği (tek görsel → sabit).
    static let identifier = "ss_rich_image"
    /// Uzantı ve MIME belirsizse varsayılan — dizi kapağı jpg'dir (07 §6.1 `cover_...jpg`).
    static let defaultFileExtension = "jpg"

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp"]
    private static let mimeToExtension: [String: String] = [
        "image/jpeg": "jpg",
        "image/jpg": "jpg",
        "image/png": "png",
        "image/gif": "gif",
        "image/heic": "heic",
        "image/heif": "heif",
        "image/webp": "webp"
    ]

    /// Attachment dosya uzantısı: önce URL yol uzantısı (tanınan bir görsel uzantısıysa), sonra yanıt MIME,
    /// en son varsayılan (`jpg`). `jpeg` → `jpg`'ye normalize edilir.
    static func fileExtension(forURL url: URL, mimeType: String?) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if imageExtensions.contains(pathExtension) {
            return normalized(pathExtension)
        }
        if let mime = normalizedMIME(mimeType), let ext = mimeToExtension[mime] {
            return ext
        }
        return defaultFileExtension
    }

    /// Yanıtın görsel olup olmadığı: MIME biliniyorsa `image/*` olmalı; bilinmiyorsa uzantıya güvenilir.
    static func isAcceptableImageResponse(mimeType: String?) -> Bool {
        guard let mime = normalizedMIME(mimeType) else { return true }
        return mime.hasPrefix("image/")
    }

    /// MIME'ı normalize eder: küçük harf + parametreleri (`; charset=...`) atar; boşsa `nil`.
    private static func normalizedMIME(_ mimeType: String?) -> String? {
        guard let base = mimeType?.lowercased().split(separator: ";").first else { return nil }
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalized(_ ext: String) -> String {
        ext == "jpeg" ? "jpg" : ext
    }
}

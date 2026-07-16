import UserNotifications

/// SS-141 — Rich push Notification Service Extension. Backend `mutable-content: 1` gönderdiğinde APNs bu
/// eklentiyi bildirim gösterilmeden önce çalıştırır: payload'daki görsel URL indirilip attachment olarak
/// eklenir ve içerik tipine göre kategori (aksiyon butonları) atanır.
///
/// TASARIM SÖZLEŞMESİ (07 §5.4): görsel indirme BEST-EFFORT'tur. İndirme başarısız / timeout / iptal /
/// görsel-olmayan yanıt durumunda push ASLA düşmez — en azından metin (ve varsa kategori) teslim edilir.
/// `serviceExtensionTimeWillExpire` sistemin son-an fallback'idir: elde ne varsa teslim eder.
///
/// Karar mantığı UN tipsiz saf çekirdektedir (`RichPushPresentation` / `RichPushAttachment`,
/// `App/Push/RichPushPlan.swift`; AppTests'te izole test edilir). Bu tip yalnız UN köprüsü + ağ
/// indirmesi + dosya işlemleridir. `contentHandler` en fazla BİR KEZ çağrılır (indirme ↔ timeout yarışı
/// bir kilitle çözülür).
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    /// `bestAttemptContent` / `contentHandler` / `downloadTask`'a, indirme tamamlanması (arka plan queue)
    /// ile `serviceExtensionTimeWillExpire` (ayrı çağrı) arasındaki yarışa karşı erişimi seri hale getirir.
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var downloadTask: URLSessionTask?

    /// NSE'ye ayrılan süre kısıtlıdır → agresif timeout. Süre dolarsa indirme başarısız sayılır ve
    /// `serviceExtensionTimeWillExpire`'ı beklemeden metin teslim edilir.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let mutableContent = request.content.mutableCopy() as? UNMutableNotificationContent
        lock.lock()
        self.contentHandler = contentHandler
        bestAttemptContent = mutableContent
        lock.unlock()

        // Mutable kopya alınamadı (teorik) → orijinal içerik (metin) teslim edilir.
        guard let mutableContent else {
            deliver(request.content)
            return
        }

        let presentation = RichPushPresentation(userInfo: request.content.userInfo)

        // Kategori (aksiyon butonları) — görsel gelmese de DAİMA uygulanır.
        if let categoryIdentifier = presentation.categoryIdentifier {
            mutableContent.categoryIdentifier = categoryIdentifier
        }

        // Görsel yok/geçersiz → indirme denemeden hemen (metin + kategori) teslim et.
        guard let imageURL = presentation.imageURL else {
            deliver(mutableContent)
            return
        }

        let task = session.downloadTask(with: imageURL) { [weak self] location, response, _ in
            self?.finishDownload(location: location, response: response, sourceURL: imageURL)
        }
        lock.lock()
        downloadTask = task
        lock.unlock()
        task.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        // Sistem eklentiyi sonlandırmak üzere: indirmeyi iptal et, elde ne varsa (en azından metin) teslim et.
        lock.lock()
        let pendingTask = downloadTask
        let fallback = bestAttemptContent
        lock.unlock()

        pendingTask?.cancel()
        if let fallback {
            deliver(fallback)
        }
    }

    /// İndirme tamamlandığında: başarılıysa attachment ekler, ne olursa olsun teslim eder (push düşmez).
    private func finishDownload(location: URL?, response: URLResponse?, sourceURL: URL) {
        lock.lock()
        let content = bestAttemptContent
        lock.unlock()

        guard let content else { return } // zaten teslim edildi (timeout kazandı) → no-op.

        let attachment = location.flatMap {
            Self.makeAttachment(downloadedAt: $0, sourceURL: sourceURL, response: response)
        }
        if let attachment {
            content.attachments = [attachment]
        }
        deliver(content)
    }

    /// `contentHandler`'ı en fazla BİR KEZ çağırır (kilit altında sahiplenip nil'ler → çift teslim yok).
    private func deliver(_ content: UNNotificationContent) {
        lock.lock()
        let handler = contentHandler
        contentHandler = nil
        lock.unlock()
        handler?(content)
    }

    /// İndirilen geçici dosyayı DOĞRU uzantıyla yeniden adlandırıp `UNNotificationAttachment` üretir.
    /// HTTP hata durumu (2xx dışı) veya görsel-olmayan MIME → `nil` (attachment eklenmez, metin teslim edilir).
    /// Uzantı/MIME kararı saf `RichPushAttachment`'tadır.
    private static func makeAttachment(
        downloadedAt location: URL,
        sourceURL: URL,
        response: URLResponse?
    ) -> UNNotificationAttachment? {
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            return nil
        }
        guard RichPushAttachment.isAcceptableImageResponse(mimeType: response?.mimeType) else {
            return nil
        }

        let fileExtension = RichPushAttachment.fileExtension(forURL: sourceURL, mimeType: response?.mimeType)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        do {
            try FileManager.default.moveItem(at: location, to: destination)
            return try UNNotificationAttachment(
                identifier: RichPushAttachment.identifier,
                url: destination,
                options: nil
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
    }
}

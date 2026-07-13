import SwiftUI

/// Küçük profil avatarı — görsel yoksa baş harfli placeholder (Profil
/// hesap kartı). Görsel yükleme feature katmanının işidir.
public struct DSAvatar: View {
    private let name: String
    private let diameter: CGFloat

    public init(name: String, diameter: CGFloat = 40) {
        self.name = name
        self.diameter = diameter
    }

    /// İlk iki kelimenin baş harfleri, locale-duyarlı büyütülmüş (test
    /// kancası). `uppercased()` locale-bağımsızdır — 'işıl' TR'de 'İ' yerine
    /// 'I' üretiyordu; bu yüzden locale parametreli büyütme zorunludur.
    static func initials(from name: String, locale: Locale = .current) -> String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map { String($0).uppercased(with: locale) }
            .joined()
    }

    /// VoiceOver etiketi: baş harf üretilemeyen isimde (boş ya da yalnız
    /// boşluk) jenerik etikete düşer (test kancası). Koşul name.isEmpty
    /// DEĞİL initials-boş'tur — '   ' isimde VoiceOver boşluk okuyordu.
    var accessibilityLabelText: String {
        Self.initials(from: name).isEmpty ? "Profil avatarı" : name
    }

    public var body: some View {
        let initials = Self.initials(from: name)
        return ZStack {
            Circle()
                .fill(DSColors.surfaceElevated)
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.textTertiary)
            } else {
                Text(verbatim: initials)
                    .font(DSTypography.captionEmphasized)
                    .foregroundStyle(DSColors.textPrimary)
                    .minimumScaleFactor(0.5)
                    .padding(DSSpacing.xxs)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay {
            Circle()
                .strokeBorder(DSColors.borderSubtle, lineWidth: DSStroke.hairline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityAddTraits(.isImage)
    }
}

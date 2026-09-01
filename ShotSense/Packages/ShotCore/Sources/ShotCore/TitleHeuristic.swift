import Foundation

/// OCR bloklarından başlık adayı seçer.
///
/// **Neden domain'de:** hem `HeuristicAnalyzer` (LLM'siz cihazlar) hem de LLM yolu boş başlık
/// döndürdüğünde bu kural devreye girer. İki farklı adaptör kullandığı ve adaptörler
/// birbirini import edemediği için (R2) saf mantık olarak `ShotCore`'da durur.
public enum TitleHeuristic {
    /// Bir ekran görüntüsünün üst bandında yer alan ve göreli olarak büyük punto ile yazılmış
    /// en uzun satır, pratikte başlıktır (uygulama adı, sayfa başlığı, gönderi konusu).
    ///
    /// Statü çubuğu (saat, pil) `maximumTopExclusion` ile dışlanır; bu bant her ekran
    /// görüntüsünde vardır ve asla başlık değildir.
    public static func title(
        from blocks: [RecognizedDocument.TextBlock],
        maximumTopExclusion: Double = 0.06,
        searchDepth: Double = 0.35,
        maximumLength: Int = 60
    ) -> String {
        let candidates = blocks.filter { block in
            block.verticalPosition > maximumTopExclusion
                && block.verticalPosition < searchDepth
                && block.text.count >= 3
                && block.text.count <= maximumLength
        }
        guard !candidates.isEmpty else {
            return blocks.first.map { String($0.text.prefix(maximumLength)) } ?? ""
        }

        // Punto (relativeHeight) ana sinyal, uzunluk ikincil ayraçtır: aynı puntodaki iki
        // satırdan daha bilgi yüklü olan seçilir.
        let best = candidates.max { lhs, rhs in
            if abs(lhs.relativeHeight - rhs.relativeHeight) > 0.005 {
                return lhs.relativeHeight < rhs.relativeHeight
            }
            return lhs.text.count < rhs.text.count
        }
        return best?.text ?? ""
    }
}

import Foundation
import Testing
@testable import DiscoverKit

@Suite("SearchInputMachine")
struct SearchInputMachineTests {
    @Test func normalizeTrimsWhitespace() {
        #expect(SearchInputMachine.normalize("  midnight  ") == "midnight")
        #expect(SearchInputMachine.normalize("\n hero \n") == "hero")
    }

    @Test func normalizeCapsAt100Characters() {
        let long = String(repeating: "a", count: 250)
        #expect(SearchInputMachine.normalize(long).count == SearchInputMachine.maxQueryLength)
    }

    @Test func belowMinLengthBrowses() {
        var machine = SearchInputMachine()
        #expect(machine.onInput("") == .browse)
        #expect(machine.onInput("m") == .browse)
    }

    @Test func minLengthSchedulesSuggest() {
        var machine = SearchInputMachine()
        let action = machine.onInput("mi")
        #expect(action == .scheduleSuggest(query: "mi", token: machine.token))
    }

    @Test func tokenIncrementsPerInput() {
        var machine = SearchInputMachine()
        _ = machine.onInput("mi")
        let first = machine.token
        _ = machine.onInput("mid")
        #expect(machine.token == first + 1)
    }

    @Test func staleTokenNotCurrentAfterNewInput() {
        var machine = SearchInputMachine()
        guard case let .scheduleSuggest(_, staleToken) = machine.onInput("mi") else {
            Issue.record("beklenen scheduleSuggest")
            return
        }
        _ = machine.onInput("mid")
        #expect(!machine.isCurrent(staleToken))
        #expect(machine.isCurrent(machine.token))
    }

    @Test func submitEmptyIgnored() {
        var machine = SearchInputMachine()
        #expect(machine.onSubmit("   ") == .ignore)
    }

    @Test func submitShowsResults() {
        var machine = SearchInputMachine()
        let action = machine.onSubmit("midnight heir")
        #expect(action == .showResults(query: "midnight heir", token: machine.token))
    }

    @Test func submitInvalidatesPendingSuggest() {
        var machine = SearchInputMachine()
        guard case let .scheduleSuggest(_, suggestToken) = machine.onInput("mid") else {
            Issue.record("beklenen scheduleSuggest")
            return
        }
        _ = machine.onSubmit("mid")
        // Gönderim token'ı artırır → askıdaki öneri yanıtı artık geçerli değil.
        #expect(!machine.isCurrent(suggestToken))
    }
}

import Foundation
import Testing
@testable import StockNotch

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private func dia(_ d: Int, hora: Int = 12) -> Date { utc.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hora))! }

@Test func valorNumInstante() {
    let p = [Ponto(em: dia(2), preco: 10), Ponto(em: dia(4), preco: 12)]
    #expect(valor(p, em: dia(1)) == 10)  // antes do primeiro: o primeiro
    #expect(valor(p, em: dia(3)) == 10)  // entre dois: o último até ali
    #expect(valor(p, em: dia(4)) == 12 && valor(p, em: dia(9)) == 12)
    #expect(valor([], em: dia(1)) == nil)
}

// Uma ação em dólar comprada no dia 3 e uma cripto em reais sempre na carteira, somadas em reais pelo câmbio de cada dia.
@Test func patrimonioAoLongoDosDias() {
    let acao = PosicaoNoTempo(serie: Serie(moeda: "USD", pontos: [Ponto(em: dia(1), preco: 100), Ponto(em: dia(4), preco: 110)]),
                              quantidade: { $0 >= dia(3) ? 2 : 0 }, custo: { $0 >= dia(3) ? (190, "USD") : nil })
    let cripto = PosicaoNoTempo(serie: Serie(moeda: "BRL", pontos: [Ponto(em: dia(1), preco: 50)]),
                                quantidade: { _ in 1 }, custo: { _ in nil })
    let cambio = ["USD": [Ponto(em: dia(1), preco: 5), Ponto(em: dia(4), preco: 6)]]
    let r = patrimonioNoTempo([acao, cripto], cambio: cambio, moeda: "BRL", instantes: [dia(2), dia(3), dia(4)])
    #expect(r.valor.map(\.preco) == [50.0, 1050, 1370])
    #expect(r.investido.map(\.preco) == [0.0, 950, 1140])

    // Sem câmbio do dólar o dia da ação fica de fora em vez de somar errado; o dia sem ela ainda conta.
    let semCambio = patrimonioNoTempo([acao, cripto], cambio: [:], moeda: "BRL", instantes: [dia(2), dia(3)])
    #expect(semCambio.valor.map(\.em) == [dia(2)])
}

@Test func fimDeCadaDia() {
    let agora = dia(4, hora: 15)
    let fins = fimDosDias(3, ate: agora, calendario: utc)
    #expect(fins == [utc.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 23, minute: 59, second: 59))!,
                     utc.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 23, minute: 59, second: 59))!,
                     agora])
}

@Test func alocacaoPorClasse() {
    let f = [Fatia(id: "1", simbolo: "BBAS3", classe: .b3, valor: 30), Fatia(id: "2", simbolo: "BTC", classe: .cripto, valor: 60),
             Fatia(id: "3", simbolo: "ETH", classe: .cripto, valor: 10)]
    let c = porClasse(f)
    #expect(c.map(\.classe) == [.b3, .cripto] && c.map(\.parte) == [0.3, 0.7])
    #expect(porClasse([]).isEmpty)
    #expect(Ativo(simbolo: "PETR4", cripto: false).classe == .b3 && Ativo(simbolo: "AAPL", cripto: false).classe == .exterior)
}

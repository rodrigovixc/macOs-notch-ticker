import Foundation
import Testing
@testable import StockNotch

private func t(_ dia: Double, _ de: String, _ qde: Double, _ para: String, _ qpara: Double) -> Troca {
    Troca(id: UUID().uuidString, em: Date(timeIntervalSince1970: dia * 86_400), de: de, qtdDe: qde, para: para, qtdPara: qpara)
}

// Compra em reais, compra em USDT pelo dólar do dia, venda pelo preço médio e troca BTC → ETH pelo BTC dado.
@Test func precoMedioPelasTrocas() {
    let precos: [String: Double] = ["USDT": 5, "BTC": 600_000]
    let trocas = [
        t(1, "BRL", 300_000, "BTC", 1),     // 1 BTC a R$ 300 mil
        t(2, "USDT", 100_000, "BTC", 1),    // 1 BTC a US$ 100 mil = R$ 500 mil
        t(3, "BTC", 0.5, "BRL", 350_000),   // venda: o médio continua R$ 400 mil
        t(4, "BTC", 0.5, "ETH", 10),        // 0,5 BTC a R$ 600 mil = R$ 300 mil por 10 ETH
        t(5, "BRL", 1, "DOGE", 1),          // moeda fora do saldo: ignorada
    ]
    let medio = precoMedioEmReais(trocas, moedas: ["BTC", "ETH", "USDT"]) { m, _ in precos[m] }
    #expect(abs(medio["BTC"]! - 400_000) < 1e-6)
    #expect(abs(medio["ETH"]! - 30_000) < 1e-6)
    #expect(medio["USDT"] == nil)  // só saiu (veio de fora): sem preço médio
    #expect(medio["DOGE"] == nil)
}

// Sem preço para avaliar, a troca fica de fora em vez de entrar com custo zero.
@Test func trocaSemPrecoFicaDeFora() {
    let medio = precoMedioEmReais([t(1, "XYZ", 10, "BTC", 1), t(2, "BRL", 200, "BTC", 1)], moedas: ["BTC"]) { _, _ in nil }
    #expect(medio["BTC"] == 200)
}

// Em reais direto, em dólar pelo dólar do dia, e o USDT (preço fixo) pelo próprio dólar.
@Test func precoContraPrecoMedio() {
    let d = { (n: Double) in Date(timeIntervalSince1970: n * 86_400) }
    let dolar = [Ponto(em: d(1), preco: 5), Ponto(em: d(2), preco: 6)]
    let emReais = contraPrecoMedio(Serie(moeda: "BRL", pontos: [Ponto(em: d(1), preco: 110)]), medio: 100, dolar: dolar)
    #expect(abs(emReais[0].preco - 0.1) < 1e-9)
    let emDolar = contraPrecoMedio(Serie(moeda: "USD", pontos: [Ponto(em: d(1), preco: 20), Ponto(em: d(2), preco: 20)]), medio: 100, dolar: dolar)
    #expect(emDolar.count == 2 && emDolar[0].preco == 0 && abs(emDolar[1].preco - 0.2) < 1e-9)
    let usdt = contraPrecoMedio(Serie(moeda: "USD", pontos: [Ponto(em: .distantPast, preco: 1)]), medio: 5, dolar: dolar)
    #expect(usdt.count == 2 && abs(usdt[1].preco - 0.2) < 1e-9)
    #expect(contraPrecoMedio(Serie(moeda: "USD", pontos: dolar), medio: 0, dolar: dolar).isEmpty)
}

import Foundation
import Testing
@testable import StockNotch

@Test func lucroPeloPrecoMedio() {
    let ativo = Ativo(simbolo: "PETR4", cripto: false, compras: [
        Compra(quantidade: 10, preco: 20, data: .now),
        Compra(quantidade: 10, preco: 30, data: .now),
    ])
    #expect(ativo.quantidade == 20)
    #expect(ativo.custo == 500)

    let ganho = resultado(custo: ativo.custo, valor: ativo.quantidade * 30)
    #expect(ganho.lucro == 100)
    #expect(ganho.percentual == 0.2)

    let perda = resultado(custo: ativo.custo, valor: ativo.quantidade * 20)
    #expect(perda.lucro == -100)
    #expect(perda.percentual == -0.2)

    #expect(resultado(custo: 0, valor: 0).percentual == 0)
}

@Test func totaisPorMoedaComBinance() {
    let petr = Ativo(simbolo: "PETR4", cripto: false, compras: [Compra(quantidade: 10, preco: 20, data: .now)])
    let aapl = Ativo(simbolo: "AAPL", cripto: false, compras: [Compra(quantidade: 2, preco: 15, data: .now)])
    let linhas = [
        Linha(ativo: petr, quantidade: 10, custo: 200, cotacao: Cotacao(preco: 30, variacao: 0.25, moeda: "BRL")),
        Linha(ativo: Ativo(simbolo: "BTC", cripto: true), quantidade: 0.5, custo: nil, cotacao: Cotacao(preco: 100, variacao: 0, moeda: "BRL")),
        Linha(ativo: Ativo(simbolo: "VALE3", cripto: false), quantidade: 0, custo: 0, cotacao: Cotacao(preco: 60, variacao: 0.1, moeda: "BRL")),
        Linha(ativo: aapl, quantidade: 2, custo: 30, cotacao: Cotacao(preco: 10, variacao: 0, moeda: "USD")),
        Linha(ativo: Ativo(simbolo: "XXXX9", cripto: false), quantidade: 5, custo: 50, cotacao: nil),
    ]
    let totais = somar(linhas)
    #expect(totais.map(\.moeda) == ["BRL", "USD"])

    let brl = totais[0]
    #expect(brl.patrimonio == 350)        // 10 × 30 + 0,5 × 100 (Binance entra no patrimônio)
    #expect(brl.hoje == 60)               // 300 − 300 / 1,25
    #expect(brl.hojePct == 60.0 / 290)
    #expect(brl.lucro.lucro == 100)       // Binance sem custo fica fora do lucro
    #expect(brl.lucro.percentual == 0.5)

    #expect(totais[1].lucro.lucro == -10)
}

@Test func simbolos() {
    #expect(Ativo(simbolo: Ativo.normalizar(" petr4 ", cripto: false), cripto: false).simboloYahoo == "PETR4.SA")
    #expect(Ativo(simbolo: "BOVA11", cripto: false).simboloYahoo == "BOVA11.SA")
    #expect(Ativo(simbolo: "AAPL", cripto: false).simboloYahoo == "AAPL")
    #expect(Ativo(simbolo: "^BVSP", cripto: false).simboloYahoo == "^BVSP")
    #expect(Ativo.normalizar("pe tr4/?ç", cripto: false) == "PETR4")
    #expect(Ativo.normalizar("btc-brl", cripto: true) == "BTC")
    #expect(Ativo.normalizar("BRL", cripto: true) == "BRL")
    #expect(Ativo(simbolo: "BTC", cripto: true).id != Ativo(simbolo: "BTC", cripto: false).id)
}

@Test func numerosComVirgula() {
    #expect(numero("1.234,56") == 1234.56)
    #expect(numero("0,05") == 0.05)
    #expect(numero("0.05") == 0.05)
    #expect(numero(" 100 ") == 100)
    #expect(numero("abc") == nil)
    #expect(numero("") == nil)
}

// Exemplo da documentação da Binance (conferido também com openssl).
@Test func assinaturaBinance() {
    let consulta = "symbol=LTCBTC&side=BUY&type=LIMIT&timeInForce=GTC&quantity=1&price=0.1&recvWindow=5000&timestamp=1499827319559"
    #expect(Binance.assinatura(consulta, segredo: "NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j")
            == "c8db56825ae71d6d79447849e617115f4a920fa2acdcab2b053c4b2838bd6b71")
}

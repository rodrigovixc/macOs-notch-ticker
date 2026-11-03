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

@Test func conversaoDeMoedas() {
    let cambio: Cambio = ["USD": 5, "EUR": 6]  // reais por unidade
    #expect(converter(10, de: "USD", para: "BRL", cambio: cambio) == 50)
    #expect(converter(50, de: "BRL", para: "USD", cambio: cambio) == 10)
    #expect(converter(6, de: "EUR", para: "USD", cambio: cambio) == 7.2)  // passa pelo real: 6 × 6 / 5
    #expect(converter(10, de: "BRL", para: "BRL", cambio: [:]) == 10)
    #expect(converter(10, de: "USD", para: "USD", cambio: [:]) == 10)
    // Sem câmbio (ou câmbio zerado) não converte: nada de número errado.
    #expect(converter(10, de: "USD", para: "BRL", cambio: [:]) == nil)
    #expect(converter(10, de: "BRL", para: "EUR", cambio: ["USD": 5]) == nil)
    #expect(converter(10, de: "GBP", para: "BRL", cambio: cambio) == nil)
    #expect(converter(10, de: "USD", para: "BRL", cambio: ["USD": 0]) == nil)
}

@Test func totalUnicoConvertido() throws {
    let petr = Ativo(simbolo: "PETR4", cripto: false, compras: [Compra(quantidade: 10, preco: 20, data: .now)])
    let aapl = Ativo(simbolo: "AAPL", cripto: false, compras: [Compra(quantidade: 2, preco: 15, data: .now)])
    let linhas = [
        Linha(ativo: petr, quantidade: 10, custo: 200, cotacao: Cotacao(preco: 30, variacao: 0.25, moeda: "BRL")),
        Linha(ativo: Ativo(simbolo: "BTC", cripto: true), quantidade: 0.5, custo: nil, cotacao: Cotacao(preco: 100, variacao: 0, moeda: "BRL")),
        Linha(ativo: Ativo(simbolo: "VALE3", cripto: false), quantidade: 0, custo: 0, cotacao: Cotacao(preco: 60, variacao: 0.1, moeda: "BRL")),
        Linha(ativo: aapl, quantidade: 2, custo: 30, cotacao: Cotacao(preco: 10, variacao: 0.25, moeda: "USD")),
        Linha(ativo: Ativo(simbolo: "XXXX9", cripto: false), quantidade: 5, custo: 50, cotacao: nil),
    ]
    let snapshot = Snapshot(cambio: ["USD": 5, "EUR": 6])

    let brl = try #require(somar(linhas, em: "BRL", cambio: snapshot.cambio))
    #expect(brl.moeda == "BRL")
    #expect(brl.patrimonio == 450)        // 10 × 30 + 0,5 × 100 (Binance entra) + 2 × 10 × 5 (AAPL em reais)
    #expect(brl.hoje == 80)               // (300 − 300 / 1,25) + (100 − 100 / 1,25)
    #expect(brl.hojePct == 80.0 / 370)
    #expect(brl.custo == 350)             // 200 + 30 × 5; Binance sem custo fica fora do lucro
    #expect(brl.lucro.lucro == 50)        // (300 − 200) + (100 − 150)
    #expect(brl.lucro.percentual == 50.0 / 350)

    let usd = try #require(somar(linhas, em: "USD", cambio: snapshot.cambio))
    #expect(usd.patrimonio == 90)         // 450 / 5
    #expect(usd.hoje == 16)
    #expect(usd.lucro.lucro == 10)
    #expect(usd.lucro.percentual == brl.lucro.percentual)  // o câmbio não muda o percentual

    // Sem o câmbio do dólar, AAPL não entra na conta: em vez de um total errado, nenhum.
    #expect(somar(linhas, em: "BRL", cambio: [:]) == nil)
    #expect(somar(linhas, em: "EUR", cambio: ["EUR": 6]) == nil)
    // Tudo em reais e exibição em reais não precisa de câmbio.
    #expect(somar(Array(linhas.prefix(3)), em: "BRL", cambio: [:])?.patrimonio == 350)
}

@Test func cambioVelho() {
    let agora = Date.now
    let snapshot = Snapshot(cambio: ["USD": 5, "EUR": 6], cambioEm: ["USD": agora, "EUR": agora - 600], em: agora)
    #expect(snapshot.cambioVelho(["USD"]) == nil)            // do mesmo ciclo
    #expect(snapshot.cambioVelho(["USD", "EUR"]) == agora - 600)  // o euro parou há 10 min
    #expect(snapshot.cambioVelho([]) == nil)                 // nada a converter
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
    // Moeda antes da primeira cotação.
    #expect(Ativo(simbolo: "PETR4", cripto: false).moedaPrevista == "BRL")
    #expect(Ativo(simbolo: "BTC", cripto: true).moedaPrevista == "BRL")
    #expect(Ativo(simbolo: "AAPL", cripto: false).moedaPrevista == "USD")
    #expect(Linha(ativo: Ativo(simbolo: "AAPL", cripto: false), quantidade: 1, custo: 10, cotacao: nil).moeda == "USD")
}

@Test func numerosComVirgula() {
    #expect(numero("1.234,56") == 1234.56)
    #expect(numero("0,05") == 0.05)
    #expect(numero("0.05") == 0.05)
    #expect(numero(" 100 ") == 100)
    #expect(numero("abc") == nil)
    #expect(numero("") == nil)
    // Em inglês a vírgula é de milhar.
    #expect(numero("1,234.56", idioma: .en) == 1234.56)
    #expect(numero("0.05", idioma: .en) == 0.05)
    #expect(numero("abc", idioma: .en) == nil)
    #expect(numero("1,234", idioma: .en) == 1234)
    #expect(numero("1,234,567.5", idioma: .en) == 1_234_567.5)
    // Vírgula decimal em inglês não é número: nil, para o form avisar em vez de gravar 3250.
    #expect(numero("32,50", idioma: .en) == nil)
    #expect(numero("0,5", idioma: .en) == nil)
    #expect(numero("1,5", idioma: .en) == nil)
    #expect(numero("1,23,456", idioma: .en) == nil)
}

@MainActor @Test func traducao() {
    #expect(tr("Carteira", "Portfolio", idioma: .pt) == "Carteira")
    #expect(tr("Carteira", "Portfolio", idioma: .en) == "Portfolio")
    let falha = Falha("Sem rede", "No network")
    #expect(mensagem(falha, idioma: .pt) == "Sem rede")
    #expect(mensagem(falha, idioma: .en) == "No network")
    // Erros do sistema seguem o idioma escolhido, não o do início do app.
    #expect(mensagem(URLError(.notConnectedToInternet), idioma: .pt) == "Sem conexão com a internet.")
    #expect(mensagem(URLError(.notConnectedToInternet), idioma: .en) == "No internet connection.")
    #expect(mensagem(ErroServico(code: -2015, msg: "Invalid API-key").falha, idioma: .pt).hasPrefix("Chave recusada"))
    #expect(mensagem(ErroServico(code: -9999, msg: "Odd").falha, idioma: .en) == "Request refused: Odd")
}

// O ICU separa o símbolo com espaço inseparável em pt_BR; troca por espaço comum para comparar.
@MainActor @Test func formatacaoPorIdioma() {
    let simples = { (texto: String) in texto.replacingOccurrences(of: "\u{00A0}", with: " ") }
    #expect(simples(dinheiro(1234.5, "BRL", idioma: .pt)) == "R$ 1.234,50")
    #expect(simples(dinheiro(1234.5, "USD", idioma: .pt)) == "US$ 1.234,50")
    #expect(dinheiro(1234.5, "USD", idioma: .en) == "$1,234.50")
    #expect(dinheiro(1234.5, "BRL", idioma: .en) == "R$1,234.50")
    #expect(simples(dinheiro(10, "EUR", sinal: true, idioma: .pt)) == "+€ 10,00")
    #expect(dinheiro(-10, "EUR", sinal: true, idioma: .en) == "-€10.00")
    #expect(pct(0.0123, idioma: .pt) == "+1,23%")
    #expect(pct(-0.0123, idioma: .en) == "-1.23%")
    #expect(qtd(1234.5, idioma: .pt) == "1.234,5")
    #expect(qtd(1234.5, idioma: .en) == "1,234.5")
}

// Usa um domínio próprio do UserDefaults para não tocar nos ajustes do app.
@MainActor @Test func ajustesPadraoEPersistencia() throws {
    let dominio = "StockNotchTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: dominio))
    defer { defaults.removePersistentDomain(forName: dominio) }

    let pt = Ajustes(defaults: defaults, linguas: ["pt-BR", "en-US"])
    #expect(pt.idioma == .pt && pt.moeda == .BRL)
    let en = Ajustes(defaults: defaults, linguas: ["en-US", "pt-BR"])
    #expect(en.idioma == .en && en.moeda == .USD)

    en.idioma = .pt
    en.moeda = .EUR
    let relido = Ajustes(defaults: defaults, linguas: ["en-US"])
    #expect(relido.idioma == .pt && relido.moeda == .EUR)
    #expect(defaults.stringArray(forKey: "AppleLanguages") == ["pt-BR"])
}

// Exemplo da documentação da Binance (conferido também com openssl).
@Test func assinaturaBinance() {
    let consulta = "symbol=LTCBTC&side=BUY&type=LIMIT&timeInForce=GTC&quantity=1&price=0.1&recvWindow=5000&timestamp=1499827319559"
    #expect(Binance.assinatura(consulta, segredo: "NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j")
            == "c8db56825ae71d6d79447849e617115f4a920fa2acdcab2b053c4b2838bd6b71")
}

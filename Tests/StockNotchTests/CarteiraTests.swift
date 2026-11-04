import Foundation
import Testing
@testable import StockNotch

// Dias fixos ao meio-dia UTC, contados num calendário UTC: o teste não depende do fuso do Mac.
private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func dia(_ d: Int, hora: Int = 12) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 9, day: d, hour: hora))!
}

private func op(_ quantidade: Double, _ preco: Double, _ data: Date) -> Operacao {
    Operacao(quantidade: quantidade, preco: preco, data: data)
}

private func posicao(_ ativo: Ativo) -> Posicao { Posicao(ativo.lancamentos(calendario: utc)) }

@Test func lucroPeloPrecoMedio() {
    let ativo = Ativo(simbolo: "PETR4", cripto: false, compras: [
        Operacao(quantidade: 10, preco: 20, data: .now),
        Operacao(quantidade: 10, preco: 30, data: .now),
    ])
    #expect(ativo.posicao.quantidade == 20)
    #expect(ativo.posicao.custo == 500)

    let ganho = resultado(custo: ativo.posicao.custo, valor: ativo.posicao.quantidade * 30)
    #expect(ganho.lucro == 100)
    #expect(ganho.percentual == 0.2)

    let perda = resultado(custo: ativo.posicao.custo, valor: ativo.posicao.quantidade * 20)
    #expect(perda.lucro == -100)
    #expect(perda.percentual == -0.2)

    #expect(resultado(custo: 0, valor: 0).percentual == 0)
}

@Test func vendasPeloPrecoMedio() {
    // Várias compras e venda parcial: o preço médio não muda com a venda.
    var ativo = Ativo(simbolo: "PETR4", cripto: false, compras: [op(10, 20, dia(1)), op(10, 30, dia(2))], vendas: [op(5, 40, dia(3))])
    var p = posicao(ativo)
    #expect(p.quantidade == 15)
    #expect(p.custo == 375)            // 500 − 5 × 25
    #expect(p.precoMedio == 25)
    #expect(p.realizado == 75)         // (40 − 25) × 5
    #expect(!p.semSaldo)

    // A ordem é a das datas, não a de cadastro: compra antiga registrada depois entra antes da venda.
    ativo.compras.append(op(10, 10, dia(1, hora: 8)))
    p = posicao(ativo)
    #expect(p.precoMedio == 20)        // (10 × 10 + 10 × 20 + 10 × 30) / 30
    #expect(p.realizado == 100)        // (40 − 20) × 5

    // Venda total zera o custo; a recompra começa um preço médio novo e o realizado fica.
    let recompra = Ativo(simbolo: "VALE3", cripto: false, compras: [op(10, 20, dia(1)), op(4, 50, dia(5))], vendas: [op(10, 30, dia(3))])
    p = posicao(recompra)
    #expect(p.quantidade == 4)
    #expect(p.custo == 200)
    #expect(p.precoMedio == 50)
    #expect(p.realizado == 100)

    // Mesmo dia: a compra conta antes da venda, mesmo gravada com hora depois.
    let mesmoDia = Ativo(simbolo: "BTC", cripto: true, compras: [op(2, 100, dia(7, hora: 18))], vendas: [op(2, 90, dia(7, hora: 9))])
    p = posicao(mesmoDia)
    #expect(p == Posicao(quantidade: 0, custo: 0, realizado: -20, semSaldo: false))

    // Arredondamento: vender 0,3 de 0,1 + 0,2 zera a posição, sem sobra nem venda sem saldo.
    let fracao = Ativo(simbolo: "ETH", cripto: true, compras: [op(0.1, 10, dia(1)), op(0.2, 10, dia(1))], vendas: [op(0.3, 20, dia(2))])
    p = posicao(fracao)
    #expect(p.quantidade == 0 && p.custo == 0 && !p.semSaldo)

    // Venda sem saldo (JSON editado à mão) não deixa quantidade negativa.
    p = posicao(Ativo(simbolo: "AAPL", cripto: false, vendas: [op(5, 10, dia(1))]))
    #expect(p.semSaldo && p.quantidade == 0 && p.realizado == 0)
}

@Test func validacaoDeVenda() {
    let ativo = Ativo(simbolo: "PETR4", cripto: false, compras: [op(10, 20, dia(2))], vendas: [op(6, 30, dia(10))])
    let agora = dia(20)
    let problema = { (venda: Bool, quantidade: Double, data: Date) in
        ativo.problema(venda: venda, quantidade: quantidade, data: data, agora: agora, calendario: utc)
    }
    #expect(ativo.maximoVenda(em: dia(1), calendario: utc) == 0)   // antes da compra
    #expect(ativo.maximoVenda(em: dia(2), calendario: utc) == 4)   // no dia da compra; a venda do dia 10 já usa 6
    #expect(ativo.maximoVenda(em: dia(5), calendario: utc) == 4)
    #expect(ativo.maximoVenda(em: dia(15), calendario: utc) == 4)

    #expect(problema(true, 4, dia(15)) == nil)
    #expect(problema(true, 5, dia(15)) == .semSaldo(disponivel: 4))
    #expect(problema(true, 1, dia(1)) == .semSaldo(disponivel: 0))
    // Vender 5 no dia 5 deixaria a venda do dia 10 sem saldo.
    #expect(problema(true, 5, dia(5)) == .semSaldo(disponivel: 4))

    // Data no futuro, por dia: hoje mais tarde ainda vale.
    #expect(problema(false, 1, dia(20, hora: 23)) == nil)
    #expect(problema(false, 1, dia(21, hora: 1)) == .dataFutura)
    #expect(problema(true, 1, dia(21)) == .dataFutura)

    // Apagar a compra deixaria a venda sem saldo; apagar a venda pode.
    #expect(!ativo.podeApagar(ativo.compras[0]))
    #expect(ativo.podeApagar(ativo.vendas[0]))
    var duas = ativo
    duas.compras.append(op(10, 25, dia(3)))
    #expect(duas.podeApagar(duas.compras[0]))
}

// O carteira.json de antes das vendas: só a lista de ativos.
@Test func arquivoAntigoContinuaLegivel() throws {
    let antigo = #"[{"simbolo":"PETR4","cripto":false,"compras":[{"id":"6F1C1D2E-0000-4000-8000-000000000001","quantidade":100,"preco":48.5,"data":"2026-09-10T12:00:00Z"}]}]"#
    let lido = try Arquivo.ler(Data(antigo.utf8))
    #expect(lido.precoMedioBinance.isEmpty)
    let ativo = try #require(lido.ativos.first)
    #expect(lido.ativos.count == 1)
    #expect(ativo.simbolo == "PETR4" && !ativo.cripto)
    #expect(ativo.vendas.isEmpty)
    #expect(ativo.compras == [Operacao(id: UUID(uuidString: "6F1C1D2E-0000-4000-8000-000000000001")!,
                                       quantidade: 100, preco: 48.5, data: dia(10))])
    #expect(ativo.posicao.custo == 4850)

    // Formato novo: grava e lê de volta igual, com vendas e preço médio da Binance.
    let novo = Arquivo(ativos: [Ativo(simbolo: "PETR4", cripto: false, compras: ativo.compras, vendas: [op(40, 52, dia(12))])],
                       precoMedioBinance: ["BTC": 350_000.5])
    #expect(try Arquivo.ler(novo.dados()) == novo)
    // Arquivo estragado dá erro: o app então não salva por cima. Sem a lista de ativos também (chave digitada
    // errado, null, objeto vazio): não é uma carteira vazia.
    #expect(throws: (any Error).self) { try Arquivo.ler(Data("[{\"simbolo\": 1}]".utf8)) }
    for estragado in [#"{"ativoss": []}"#, #"{"ativos": null}"#, "{}", #"{"precoMedioBinance": {"BTC": 1}}"#] {
        #expect(throws: (any Error).self) { try Arquivo.ler(Data(estragado.utf8)) }
    }
}

// Do disco: só "não há nada no caminho" vira carteira vazia. Qualquer outro problema de leitura é erro, para o app
// não gravar uma carteira vazia por cima. Numa pasta temporária: nada de tocar no carteira.json de verdade.
@Test func arquivoNoDisco() throws {
    let fm = FileManager.default
    let pasta = fm.temporaryDirectory.appending(path: "StockNotchTests-\(UUID().uuidString)")
    try fm.createDirectory(at: pasta, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: pasta) }

    #expect(try Arquivo.abrir(pasta.appending(path: "carteira.json")) == nil)
    let bom = pasta.appending(path: "bom.json")
    let novo = Arquivo(ativos: [Ativo(simbolo: "PETR4", cripto: false, compras: [op(1, 10, dia(1))])])
    try novo.dados().write(to: bom)
    #expect(try Arquivo.abrir(bom) == novo)

    // Pasta, link quebrado ou arquivo sem permissão no lugar do carteira.json.
    let pastaNoLugar = pasta.appending(path: "pasta.json")
    try fm.createDirectory(at: pastaNoLugar, withIntermediateDirectories: true)
    #expect(throws: (any Error).self) { try Arquivo.abrir(pastaNoLugar) }
    let link = pasta.appending(path: "link.json")
    try fm.createSymbolicLink(at: link, withDestinationURL: pasta.appending(path: "sumiu.json"))
    #expect(throws: (any Error).self) { try Arquivo.abrir(link) }
    let trancado = pasta.appending(path: "trancado.json")
    try novo.dados().write(to: trancado)
    try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: trancado.path)
    #expect(throws: (any Error).self) { try Arquivo.abrir(trancado) }
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
    #expect(converter(0, de: "USD", para: "BRL", cambio: [:]) == 0)  // zero não pede câmbio
}

@Test func totalUnicoConvertido() throws {
    let petr = Ativo(simbolo: "PETR4", cripto: false, compras: [Operacao(quantidade: 10, preco: 20, data: .now)])
    let aapl = Ativo(simbolo: "AAPL", cripto: false, compras: [Operacao(quantidade: 2, preco: 15, data: .now)])
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
    #expect(brl.aberto.lucro == 50)       // (300 − 200) + (100 − 150)
    #expect(brl.aberto.percentual == 50.0 / 350)

    let usd = try #require(somar(linhas, em: "USD", cambio: snapshot.cambio))
    #expect(usd.patrimonio == 90)         // 450 / 5
    #expect(usd.hoje == 16)
    #expect(usd.aberto.lucro == 10)
    #expect(usd.aberto.percentual == brl.aberto.percentual)  // o câmbio não muda o percentual

    // Sem o câmbio do dólar, AAPL não entra na conta: em vez de um total errado, nenhum.
    #expect(somar(linhas, em: "BRL", cambio: [:]) == nil)
    #expect(somar(linhas, em: "EUR", cambio: ["EUR": 6]) == nil)
    // Tudo em reais e exibição em reais não precisa de câmbio.
    #expect(somar(Array(linhas.prefix(3)), em: "BRL", cambio: [:])?.patrimonio == 350)
}

@Test func realizadoNoTotalENaLinha() throws {
    let usd = Cotacao(preco: 10, variacao: 0, moeda: "USD")
    // Posição zerada em dólar: só o realizado entra, convertido.
    let encerrada = Linha(ativo: Ativo(simbolo: "AAPL", cripto: false), quantidade: 0, custo: 0, cotacao: usd, realizado: 20)
    // Venda parcial em reais: em aberto e realizado separados.
    let parcial = Linha(ativo: Ativo(simbolo: "PETR4", cripto: false), quantidade: 15, custo: 375,
                        cotacao: Cotacao(preco: 30, variacao: 0, moeda: "BRL"), realizado: 75)
    // Saldo da Binance com preço médio entra no em aberto.
    let binance = Linha(ativo: Ativo(simbolo: "BTC", cripto: true), quantidade: 0.5, custo: 0.5 * 80,
                        cotacao: Cotacao(preco: 100, variacao: 0, moeda: "BRL"), binance: true)
    let cambio: Cambio = ["USD": 5]

    let t = try #require(somar([encerrada, parcial, binance], em: "BRL", cambio: cambio))
    #expect(t.patrimonio == 500)          // 15 × 30 + 0,5 × 100
    #expect(t.custo == 415)
    #expect(t.aberto.lucro == 85)         // (450 − 375) + (50 − 40)
    #expect(t.realizado == 175)           // 20 × 5 + 75
    // Sem câmbio do dólar, nem o realizado da AAPL entra: nada de total errado.
    #expect(somar([encerrada, parcial], em: "BRL", cambio: [:]) == nil)

    // A linha passa pela mesma conta; sem câmbio fica na moeda do ativo.
    let linha = resumir(encerrada, em: "BRL", cambio: cambio)
    #expect(linha.moeda == "BRL" && linha.realizado == 100 && linha.patrimonio == 0)
    let semCambio = resumir(encerrada, em: "BRL", cambio: [:])
    #expect(semCambio.moeda == "USD" && semCambio.realizado == 20)
    #expect(resumir(parcial, em: "BRL", cambio: [:]).aberto.lucro == 75)
    #expect(binance.id == "binance:c:BTC" && parcial.id == "a:PETR4")
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
    #expect(numero("0,050", idioma: .en) == nil)  // seria 50: zero à esquerda não começa grupo de milhar
    #expect(numero(".5", idioma: .en) == 0.5)

    // Em português o ponto antes de grupos de três dígitos é milhar, como o app mostra: "350.000" é 350 mil, não 350.
    #expect(numero("350.000") == 350_000)
    #expect(numero("600.000") == 600_000)
    #expect(numero("1.234.567,89") == 1_234_567.89)
    // Sem poder ser milhar, o ponto é decimal.
    #expect(numero("0.050") == 0.05)
    #expect(numero("12.50") == 12.5)
    #expect(numero("1.2345") == 1.2345)
    // Formato do outro idioma, ou o que o Double() aceitaria mas não é um número digitado: nil, para o form avisar.
    #expect(numero("1,234.56") == nil)
    #expect(numero("1.23.4") == nil)
    for estranho in ["inf", "nan", "1e400", "0x10", "-5", "1 234", "5%"] {
        #expect(numero(estranho) == nil && numero(estranho, idioma: .en) == nil)
    }
    #expect(numero(String(repeating: "9", count: 400)) == nil)  // só dígitos, mas infinito
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
    // A explicação da Binance é só em inglês: em português fica o código.
    #expect(mensagem(ErroServico(code: -9999, msg: "Odd").falha, idioma: .en) == "Request refused by Binance: Odd")
    #expect(mensagem(ErroServico(code: -9999, msg: "Odd").falha, idioma: .pt) == "Pedido recusado pela Binance (código -9999).")
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

    // Widget: no notch, variação, 4 s e tudo girando até alguém mudar.
    #expect(relido.posicao == .notch && relido.estilo == .variacao && relido.ritmo == 4)
    #expect(relido.foraDoLetreiro.isEmpty && relido.ancoraLivre == nil)
    relido.posicao = .livre
    relido.estilo = .completo
    relido.ritmo = 10
    relido.foraDoLetreiro = ["a:AAPL", "binance:c:BNB"]
    relido.ancoraLivre = CGPoint(x: 1720.5, y: 900)
    let widget = Ajustes(defaults: defaults, linguas: ["en-US"])
    #expect(widget.posicao == .livre && widget.estilo == .completo && widget.ritmo == 10)
    #expect(widget.foraDoLetreiro == ["a:AAPL", "binance:c:BNB"] && widget.ancoraLivre == CGPoint(x: 1720.5, y: 900))
    widget.ancoraLivre = nil
    #expect(Ajustes(defaults: defaults, linguas: ["en-US"]).ancoraLivre == nil)
}

// Exemplo da documentação da Binance (conferido também com openssl).
@Test func assinaturaBinance() {
    let consulta = "symbol=LTCBTC&side=BUY&type=LIMIT&timeInForce=GTC&quantity=1&price=0.1&recvWindow=5000&timestamp=1499827319559"
    #expect(Binance.assinatura(consulta, segredo: "NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j")
            == "c8db56825ae71d6d79447849e617115f4a920fa2acdcab2b053c4b2838bd6b71")
}

// Resposta do apiRestrictions com os campos da documentação da Binance. A chave só de leitura passa; qualquer
// permissão ligada além da leitura recusa, inclusive as que o app não conhece.
@Test func chaveSoDeLeitura() throws {
    let resposta = #"{"ipRestrict":false,"createTime":1698645219000,"enableReading":true,"enableWithdrawals":false,"enableInternalTransfer":false,"enableMargin":false,"enableFutures":false,"permitsUniversalTransfer":false,"enableVanillaOptions":false,"enableFixApiTrade":false,"enableFixReadOnly":true,"enableSpotAndMarginTrading":false,"enablePortfolioMarginTrading":false}"#
    let ler = { (json: String) in try JSONDecoder().decode(Permissoes.self, from: Data(json.utf8)) }
    let ligando = { (campo: String) in resposta.replacingOccurrences(of: "\"\(campo)\":false", with: "\"\(campo)\":true") }
    #expect(try ler(resposta).soLeitura)
    #expect(try ler(ligando("ipRestrict")).soLeitura)  // restrição de IP só ajuda
    for perigosa in ["enableVanillaOptions", "enablePortfolioMarginTrading", "enableFixApiTrade", "enableWithdrawals", "permitsUniversalTransfer"] {
        #expect(try !ler(ligando(perigosa)).soLeitura, "\(perigosa)")
    }
    #expect(try !ler(resposta.replacingOccurrences(of: #""enableReading":true"#, with: #""enableReading":false"#)).soLeitura)
    // Uma permissão que a Binance criar depois também recusa.
    #expect(try !ler(#"{"enableReading":true,"enableAlgoNovo":true}"#).soLeitura)
}

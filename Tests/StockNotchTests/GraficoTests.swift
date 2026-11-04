import Foundation
import Testing
@testable import StockNotch

// Amostras reais capturadas em 03/11/2026 às 19:17 BRT (22:17 UTC), depois do fechamento da B3; só algumas barras.

// Chart do Yahoo com interval=5m&range=1d. PETR4: barras de 10:05 a 17:00 (a grade do Yahoo), a última com o fechamento
// do leilão; o meta é o mesmo da cotação.
private let barrasPETR4 = #"{"chart":{"result":[{"meta":{"currency":"BRL","symbol":"PETR4.SA","exchangeName":"SAO","regularMarketTime":1793739945,"regularMarketPrice":50.71,"chartPreviousClose":52.71,"previousClose":52.71,"currentTradingPeriod":{"pre":{"timezone":"BRT","end":1793710800,"start":1793709900,"gmtoffset":-10800},"regular":{"timezone":"BRT","end":1793736000,"start":1793710800,"gmtoffset":-10800},"post":{"timezone":"BRT","end":1793739600,"start":1793736000,"gmtoffset":-10800}},"dataGranularity":"5m","range":"1d"},"timestamp":[1793711100,1793711400,1793735700,1793736000],"indicators":{"quote":[{"open":[51.20000076293945,51.02000045776367,50.59000015258789,50.709999084472656],"volume":[0,1736600,630100,0],"close":[51.02000045776367,50.68000030517578,50.72999954223633,50.709999084472656]}]}}],"error":null}}"#

// USD-BRL desde 00:00 UTC: barra sem negócio vem null, e a última é a do horário da cotação.
private let barrasUSDBRL = #"{"chart":{"result":[{"meta":{"currency":"BRL","symbol":"USDBRL=X","exchangeName":"CCY","regularMarketTime":1793743461,"regularMarketPrice":5.4895,"chartPreviousClose":5.4366,"previousClose":5.4366,"dataGranularity":"5m","range":"1d"},"timestamp":[1793669700,1793670000,1793670300,1793742900,1793743200,1793743461],"indicators":{"quote":[{"open":[5.436600208282471,5.436600208282471,null,5.491099834442139,5.491099834442139,5.489500045776367],"close":[5.436600208282471,5.436600208282471,null,5.491099834442139,5.48829984664917,5.489500045776367]}]}}],"error":null}}"#

// Velas de 15 min do BTCUSDT desde 00:00 UTC: as duas primeiras e a em curso (fecha às 22:29:59, no futuro).
private let velasBTC = #"[[1793664000000,"76816.01000000","76878.01000000","76663.90000000","76816.00000000","123.49346000",1793664899999,"9478603.96809670",24072,"64.78373000","4973224.04161940","0"],[1793664900000,"76816.01000000","77062.03000000","76802.00000000","77060.00000000","91.77066000",1793665799999,"7066465.04168080",22918,"64.77426000","4987769.19817390","0"],[1793744100000,"77812.97000000","77833.75000000","77812.97000000","77833.74000000","4.54418000",1793744999999,"353620.16137020",818,"3.01025000","234258.52757390","0"]]"#

private func t(_ segundos: TimeInterval) -> Date { Date(timeIntervalSince1970: segundos) }
private func yahoo(_ json: String) throws -> RespostaYahoo { try JSONDecoder().decode(RespostaYahoo.self, from: Data(json.utf8)) }

// A PETR4 depois do leilão, como o app a recebe: −3,79% contra o fechamento de ontem.
private let petr = Cotacao(preco: 50.71, variacao: 50.71 / 52.71 - 1, moeda: "BRL", em: t(1793739945), recebida: t(1793744266),
                           atraso: 900, pregao: DateInterval(start: t(1793710800), end: t(1793736000)))
// O BTC do stream às 22:17:46 UTC, com a variação desde a abertura das 00:00 UTC.
private let btc = Cotacao(preco: 77_840, variacao: 77_840 / 76_816.01 - 1, moeda: "USD", em: t(1793744266), recebida: t(1793744266))

@Test func serieDoYahoo() throws {
    let s = try yahoo(barrasPETR4).serie()
    #expect(s.moeda == "BRL")
    #expect(s.pontos.map(\.em) == [t(1793711100), t(1793711400), t(1793735700), t(1793736000)])
    #expect(s.pontos.map(\.preco) == [51.02000045776367, 50.68000030517578, 50.72999954223633, 50.709999084472656])
    // A mesma resposta ainda dá a cotação: o meta não mudou.
    #expect(try yahoo(barrasPETR4).cotacao().preco == 50.71)

    // Barra sem negócio (null) fica de fora em vez de virar preço zero.
    let dolar = try yahoo(barrasUSDBRL).serie()
    #expect(dolar.pontos.count == 5 && !dolar.pontos.contains { $0.em == t(1793670300) })
    #expect(dolar.pontos.last == Ponto(em: t(1793743461), preco: 5.489500045776367))

    // Resposta só com o meta (a da cotação, sem barras) não tem desenho; sem resultado é erro.
    #expect(try yahoo(#"{"chart":{"result":[{"meta":{"currency":"USD","regularMarketPrice":1,"chartPreviousClose":1}}]}}"#).serie().pontos.isEmpty)
    #expect(throws: (any Error).self) { try yahoo(#"{"chart":{"result":null}}"#).serie() }

    // Abertura da B3 antes do primeiro negócio (04/11/2026 às 10:18): o dia virou, as barras vêm vazias, sem "close".
    // A cotação tem que sair mesmo assim, com o fechamento de ontem e variação zero, e o mercado conta como fechado.
    let abertura = try yahoo(#"{"chart":{"result":[{"meta":{"currency":"BRL","exchangeName":"SAO","regularMarketTime":1793739945,"regularMarketPrice":50.71,"chartPreviousClose":50.71,"previousClose":50.71,"currentTradingPeriod":{"regular":{"start":1793797200,"end":1793822400}}},"indicators":{"quote":[{}]}}]}}"#)
    let c = try abertura.cotacao(recebida: t(1793798325))
    #expect(c.preco == 50.71 && c.variacao == 0 && c.selo(agora: t(1793798325)) == .fechado)
    #expect(try abertura.serie().pontos.isEmpty)
}

@Test func serieDaBinance() throws {
    let velas = try JSONDecoder().decode([VelaBinance].self, from: Data(velasBTC.utf8))
    let s = Serie(velas: velas, moeda: "USD")
    // Sai da abertura das 00:00 UTC (a referência da variação) e cada vela entra no fim dela, com o fechamento.
    #expect(s.pontos == [Ponto(em: t(1793664000), preco: 76_816.01), Ponto(em: t(1793664899.999), preco: 76_816),
                         Ponto(em: t(1793665799.999), preco: 77_060), Ponto(em: t(1793744999.999), preco: 77_833.74)])
    #expect(Serie(velas: [], moeda: "USD").pontos.isEmpty)
    // Preço estragado é erro, não ponto no zero.
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode([VelaBinance].self, from: Data(velasBTC.replacingOccurrences(of: "\"77060.00000000\"", with: "\"0\"").utf8))
    }
}

@Test func ultimoPontoBateComOPreco() throws {
    let barras = try yahoo(barrasPETR4).serie().pontos
    // Depois do fechamento: as barras até 17:00 e a cotação do leilão (18:05:45) como último ponto.
    let fechado = ajustar(barras, a: petr)
    #expect(fechado == barras + [Ponto(em: t(1793739945), preco: 50.71)])
    #expect(abs(petr.referencia - 52.71) < 1e-9)  // o tracejado no fechamento de ontem
    #expect(fechado.last!.preco < petr.referencia)  // linha abaixo do tracejado: vermelha, como a variação

    // Série mais nova que a cotação (buscada depois dela): a barra posterior sai e o fim é o preço mostrado.
    var antes = petr
    antes.em = t(1793735800)
    antes.preco = 50.6
    #expect(ajustar(barras, a: antes) == Array(barras.prefix(3)) + [Ponto(em: t(1793735800), preco: 50.6)])

    // Amanhã às 10:20 com a série de hoje (ainda não buscada de novo): nada de hoje entra no desenho de amanhã.
    let dia: TimeInterval = 86_400
    var amanha = petr
    amanha.em = t(1793711100 + dia)
    amanha.pregao = DateInterval(start: t(1793710800 + dia), end: t(1793736000 + dia))
    #expect(ajustar(barras, a: amanha) == [Ponto(em: amanha.em, preco: 50.71)])
    // Antes da abertura de amanhã o negócio ainda é de hoje: o desenho de hoje continua.
    var madrugada = petr
    madrugada.pregao = amanha.pregao
    #expect(ajustar(barras, a: madrugada) == fechado)

    // Cripto: a vela em curso (fecha no futuro) sai e o preço do stream fecha a linha, que sai da referência.
    let velas = Serie(velas: try JSONDecoder().decode([VelaBinance].self, from: Data(velasBTC.utf8)), moeda: "USD").pontos
    let agora = ajustar(velas, a: btc)
    #expect(agora == Array(velas.prefix(3)) + [Ponto(em: t(1793744266), preco: 77_840)])
    #expect(abs(agora[0].preco - btc.referencia) < 1e-6)
    // Passou das 00:00 UTC: a variação zerou, e a série de ontem não entra.
    var depois = btc
    depois.em = t(1793750400 + 30)
    #expect(ajustar(velas, a: depois).count == 1)
}

@Test func minigraficoNoSnapshot() throws {
    let agora = t(1793744266)
    var fontes = Fontes()
    fontes.acoes["a:PETR4"] = petr
    fontes.series["a:PETR4"] = try yahoo(barrasPETR4).serie()
    fontes.cripto["c:BTC"] = btc
    fontes.series["c:BTC"] = Serie(velas: try JSONDecoder().decode([VelaBinance].self, from: Data(velasBTC.utf8)), moeda: "USD")
    fontes.cambio["USD"] = Cotacao(preco: 5.4895, variacao: 5.4895 / 5.4366 - 1, moeda: "BRL", em: agora, recebida: agora)
    fontes.serieDolar = try yahoo(barrasUSDBRL).serie().pontos
    let s = Snapshot(fontes, agora: agora)
    let bitcoin = Ativo(simbolo: "BTC", cripto: true)

    // Ação na moeda dela, terminando no preço da linha.
    let acao = try #require(s.serie(Ativo(simbolo: "PETR4", cripto: false), ate: petr))
    #expect(acao.count == 5 && acao.last == Ponto(em: petr.em, preco: 50.71))

    // Cripto em reais: cada ponto em dólar × o dólar daquele momento, terminando no preço em reais da tela.
    let reais = try #require(s.cotacao(bitcoin, moeda: "BRL"))
    let r = try #require(s.serie(bitcoin, ate: reais))
    #expect(r.count == 4 && r.last == Ponto(em: reais.em, preco: reais.preco))
    // O primeiro dólar do dia é o fechamento anterior do câmbio: a linha sai do tracejado também em reais.
    #expect(abs(r[0].preco / reais.referencia - 1) < 1e-6)
    // Em dólar, a série como veio, terminando no BTC-USD.
    let dolares = try #require(s.cotacao(bitcoin, moeda: "USD"))
    #expect(s.serie(bitcoin, ate: dolares)?.last == Ponto(em: agora, preco: 77_840))

    // Sem a série do dólar, em reais não há desenho (em dólar continua); nem com preço fixo ou moeda que não bate.
    var semDolar = fontes
    semDolar.serieDolar = []
    let s2 = Snapshot(semDolar, agora: agora)
    #expect(s2.serie(bitcoin, ate: try #require(s2.cotacao(bitcoin, moeda: "BRL"))) == nil)
    #expect(s2.serie(bitcoin, ate: dolares) != nil)
    var fixa = fontes
    fixa.series["c:USDT"] = fontes.series["c:BTC"]
    let usdt = Ativo(simbolo: "USDT", cripto: true)
    #expect(Snapshot(fixa, agora: agora).serie(usdt, ate: try #require(s.cotacao(usdt, moeda: "BRL"))) == nil)
    var outraMoeda = btc
    outraMoeda.moeda = "EUR"
    #expect(s.serie(bitcoin, ate: outraMoeda) == nil)
}

@Test func criptoConvertidaPeloDolarDaquelaHora() {
    let pontos = [Ponto(em: t(0), preco: 10), Ponto(em: t(150), preco: 10), Ponto(em: t(300), preco: 10)]
    let dolar = [Ponto(em: t(100), preco: 5), Ponto(em: t(200), preco: 6)]
    // Antes do primeiro câmbio vale o primeiro; depois, o último até ali.
    #expect(emReais(pontos, dolar: dolar).map(\.preco) == [50, 50, 60])
    #expect(emReais(pontos, dolar: []).isEmpty)
}

// Cotação completa do Yahoo (v7/quote) de 04/11/2026, só alguns campos: o que o detalhe do notch mostra.
@Test func indicadoresDoYahoo() throws {
    let json = #"{"quoteResponse":{"result":[{"symbol":"PETR4.SA","currency":"BRL","regularMarketOpen":50.04,"regularMarketDayHigh":50.31,"regularMarketDayLow":48.91,"regularMarketPreviousClose":50.71,"regularMarketVolume":19361000,"averageDailyVolume3Month":51279641,"fiftyTwoWeekHigh":59.79,"fiftyTwoWeekLow":29.53,"marketCap":668417720320,"trailingPE":4.663489,"epsTrailingTwelveMonths":10.49,"dividendYield":7.23,"priceToBook":1.3109657}],"error":null}}"#
    struct R: Decodable { struct L: Decodable { let result: [Indicadores] }; let quoteResponse: L }
    let i = try #require(try JSONDecoder().decode(R.self, from: Data(json.utf8)).quoteResponse.result.first)
    #expect(i.currency == "BRL" && i.regularMarketOpen == 50.04 && i.marketCap == 668_417_720_320)
    #expect(i.trailingPE == 4.663489 && i.dividendYield == 7.23 && i.fiftyTwoWeekLow == 29.53)
    // Ação sem fundamentos (ETF, recém-listada): os campos faltam e a resposta continua legível.
    let vazio = try JSONDecoder().decode(Indicadores.self, from: Data(#"{"currency":"USD"}"#.utf8))
    #expect(vazio.trailingPE == nil && vazio.marketCap == nil)
}

// Busca do Yahoo (04/11/2026, "itau" e "bitcoin" juntas): fundo, futuro e cripto fora do dólar ficam de fora.
@Test func buscaDeAtivos() throws {
    let json = #"{"quotes":[{"symbol":"ITUB","shortname":"Itau Unibanco Banco Holding SA","quoteType":"EQUITY","exchDisp":"NYSE"},{"symbol":"ITUB4.SA","shortname":"ITAUUNIBANCOPN      N1","quoteType":"EQUITY","exchDisp":"São Paulo"},{"symbol":"0P0001VQAW.SA","quoteType":"MUTUALFUND","exchDisp":"São Paulo"},{"symbol":"BTC-USD","shortname":"Bitcoin USD","quoteType":"CRYPTOCURRENCY","exchDisp":"CCC"},{"symbol":"BTC-EUR","shortname":"Bitcoin EUR","quoteType":"CRYPTOCURRENCY"},{"symbol":"IBIT","longname":"iShares Bitcoin Trust ETF","quoteType":"ETF","exchDisp":"NASDAQ"},{"symbol":"BTC=F","quoteType":"FUTURE"}]}"#
    let s = try JSONDecoder().decode(RespostaBusca.self, from: Data(json.utf8)).sugestoes
    #expect(s.map(\.id) == ["a:ITUB", "a:ITUB4", "c:BTC", "a:IBIT"])
    #expect(s[1].nome == "ITAUUNIBANCOPN N1" && s[1].bolsa == "São Paulo" && s[2].cripto)
}

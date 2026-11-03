import Foundation
import Testing
@testable import StockNotch

// Amostras reais capturadas em 03/11/2026 (terça, B3 no primeiro dia do pregão até 17:55 + leilão até 18:00).

// Stream combinado da Binance, 18:19:06 BRT.
private let velaBTC = #"{"stream":"btcusdt@kline_1d","data":{"e":"kline","E":1793740746023,"s":"BTCUSDT","k":{"t":1793664000000,"T":1793750399999,"s":"BTCUSDT","i":"1d","f":6813483549,"L":6816057453,"o":"76816.01000000","c":"77970.00000000","h":"77970.01000000","l":"76388.88000000","v":"11998.88735000","n":2573905,"x":false,"q":"925716659.16790480","V":"5894.97927000","Q":"455066812.25583360","B":"0"}}}"#

// Chart do Yahoo às 17:38:50 BRT, só o meta (sem as listas de períodos).
private func chart(_ meta: String) -> Data { Data(#"{"chart":{"result":[{"meta":\#(meta)}],"error":null}}"#.utf8) }

private let metaPETR4 = #"{"currency":"BRL","symbol":"PETR4.SA","exchangeName":"SAO","fullExchangeName":"São Paulo","instrumentType":"EQUITY","regularMarketTime":1793737430,"hasPrePostMarketData":false,"gmtoffset":-10800,"timezone":"BRT","exchangeTimezoneName":"America/Sao_Paulo","regularMarketPrice":50.68,"regularMarketChangePercent":-3.851,"regularMarketDayHigh":51.21,"regularMarketDayLow":49.15,"chartPreviousClose":52.71,"previousClose":52.71,"scale":3,"priceHint":2,"currentTradingPeriod":{"pre":{"timezone":"BRT","end":1793710800,"start":1793709900,"gmtoffset":-10800},"regular":{"timezone":"BRT","end":1793736000,"start":1793710800,"gmtoffset":-10800},"post":{"timezone":"BRT","end":1793739600,"start":1793736000,"gmtoffset":-10800}},"dataGranularity":"1m","range":"1d"}"#

private let metaAAPL = #"{"currency":"USD","symbol":"AAPL","exchangeName":"NMS","fullExchangeName":"NasdaqGS","instrumentType":"EQUITY","regularMarketTime":1793738331,"hasPrePostMarketData":true,"gmtoffset":-18000,"timezone":"EST","exchangeTimezoneName":"America/New_York","regularMarketPrice":330.21,"chartPreviousClose":338.32,"previousClose":338.32,"currentTradingPeriod":{"pre":{"timezone":"EST","start":1793696400,"end":1793716200,"gmtoffset":-18000},"regular":{"timezone":"EST","start":1793716200,"end":1793739600,"gmtoffset":-18000},"post":{"timezone":"EST","start":1793739600,"end":1793754000,"gmtoffset":-18000}},"dataGranularity":"1m","range":"1d"}"#

private let metaUSDBRL = #"{"currency":"BRL","symbol":"USDBRL=X","exchangeName":"CCY","fullExchangeName":"CCY","instrumentType":"CURRENCY","regularMarketTime":1793738330,"gmtoffset":0,"timezone":"GMT","exchangeTimezoneName":"Europe/London","regularMarketPrice":5.4957,"chartPreviousClose":5.4366,"previousClose":5.4366,"currentTradingPeriod":{"pre":{"timezone":"GMT","start":1793664000,"end":1793664000,"gmtoffset":0},"regular":{"timezone":"GMT","start":1793664000,"end":1793750340,"gmtoffset":0},"post":{"timezone":"GMT","start":1793750340,"end":1793750340,"gmtoffset":0}},"dataGranularity":"1m","range":"1d"}"#

private func t(_ segundos: TimeInterval) -> Date { Date(timeIntervalSince1970: segundos) }

@Test func mensagensDoStream() {
    let recebida = t(1793740746.2)
    let vela = MensagemBinance(velaBTC, recebida: recebida)
    #expect(vela == .cotacao(moeda: "BTC", Cotacao(preco: 77970, variacao: 77970 / 76816.01 - 1, moeda: "USD",
                                                     em: t(1793740746.023), recebida: recebida)))
    if case .cotacao(_, let c) = vela { #expect(abs(c.variacao - 0.015023) < 1e-6) }  // +1,50% desde 00:00 UTC

    // A Binance avisa antes de derrubar a conexão. Exemplos da documentação (um real não deu para capturar):
    // com o envelope do stream combinado e sem ele; os dois valem.
    #expect(MensagemBinance(#"{"stream":"!serverShutdown","data":{"e":"serverShutdown","E":1770123456789}}"#) == .desligando)
    #expect(MensagemBinance(#"{"e":"serverShutdown","E":1770123456789}"#) == .desligando)
    // O resto é ignorado: resposta de assinatura, par fora do USDT, abertura zero, texto estragado.
    #expect(MensagemBinance(#"{"result":null,"id":1}"#) == nil)
    #expect(MensagemBinance(velaBTC.replacingOccurrences(of: "BTCUSDT", with: "ETHBTC")) == nil)
    #expect(MensagemBinance(velaBTC.replacingOccurrences(of: #""o":"76816.01000000""#, with: #""o":"0""#)) == nil)
    #expect(MensagemBinance("{oi") == nil)
}

@Test func cotacaoDoYahooComHorarioEPregao() throws {
    let recebida = t(1793738330)
    let petr = try JSONDecoder().decode(RespostaYahoo.self, from: chart(metaPETR4)).cotacao(recebida: recebida)
    #expect(petr.preco == 50.68 && petr.moeda == "BRL")
    #expect(petr.variacao == 50.68 / 52.71 - 1)  // contra o fechamento anterior: −3,85%, como no Google
    #expect(petr.em == t(1793737430))           // 17:23:50: os 15 min de atraso
    #expect(petr.atraso == 900)
    #expect(petr.pregao == DateInterval(start: t(1793710800), end: t(1793736000)))

    let aapl = try JSONDecoder().decode(RespostaYahoo.self, from: chart(metaAAPL)).cotacao(recebida: recebida)
    #expect(aapl.atraso == 0 && aapl.variacao == 330.21 / 338.32 - 1)

    let dolar = try JSONDecoder().decode(RespostaYahoo.self, from: chart(metaUSDBRL)).cotacao(recebida: recebida)
    #expect(dolar.atraso == 0 && dolar.variacao == 5.4957 / 5.4366 - 1)  // desde 00:00 UTC

    // Bolsa sem atraso conhecido não promete "ao vivo"; sem regularMarketTime, o horário é o da chegada.
    let outra = try JSONDecoder().decode(RespostaYahoo.self, from: chart(#"{"currency":"GBp","exchangeName":"LSE","regularMarketPrice":10,"chartPreviousClose":8}"#))
        .cotacao(recebida: recebida)
    #expect(outra.atraso == nil && outra.em == recebida && outra.pregao == nil && outra.variacao == 0.25)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(RespostaYahoo.self, from: Data(#"{"chart":{"result":null}}"#.utf8)).cotacao() }
}

@Test func regrasDeIdade() throws {
    // B3 às 17:38:52 com a grade errada do Yahoo (fim às 17:00): o negócio das 17:23:50 estende o pregão.
    let petr = try JSONDecoder().decode(RespostaYahoo.self, from: chart(metaPETR4)).cotacao(recebida: t(1793738330))
    let agora = t(1793738332)
    #expect(petr.aberto(agora: agora))
    #expect(petr.selo(agora: agora) == .atraso(900))
    // Último negócio às 18:00 (visto às 18:15): às 18:25 o dado já mostra o mercado fechado.
    var fechamento = petr
    fechamento.em = t(1793739600)
    fechamento.recebida = t(1793741090)
    #expect(fechamento.selo(agora: t(1793741100)) == .fechado)
    // Às 10:10 de hoje o dado (15 min atrasado) ainda é de antes da abertura: fechado.
    var manha = petr
    manha.em = t(1793739600 - 86400)
    manha.recebida = t(1793711400)
    #expect(manha.selo(agora: t(1793711400)) == .fechado)

    // EUA: ao vivo durante o pregão; fechado logo depois das 16:00 (sem estender) e em feriado (sem negócio hoje).
    let aapl = try JSONDecoder().decode(RespostaYahoo.self, from: chart(metaAAPL)).cotacao(recebida: t(1793738331))
    #expect(aapl.selo(agora: t(1793738335)) == .aoVivo)
    var depois = aapl
    depois.em = t(1793739600)
    depois.recebida = t(1793739630)
    #expect(depois.selo(agora: t(1793739630)) == .fechado)
    var feriado = aapl
    feriado.em = t(1793739600 - 86400)
    #expect(feriado.selo(agora: t(1793738335)) == .fechado)
    // Chegou agora, mas o horário da cotação parou há 5 min com o pregão aberto: preço congelado, nada de "ao vivo".
    var congelada = aapl
    congelada.em = t(1793738331 - 300)
    #expect(congelada.selo(agora: t(1793738335)) == .horario(t(1793738031)))
    // O "15 min" da B3 também precisa do horário confirmando: às 16:55, uma cotação das 16:30 é só o horário.
    var parada = petr
    parada.em = t(1793736000 - 1800)
    parada.recebida = t(1793736000 - 300)
    #expect(parada.selo(agora: t(1793736000 - 300)) == .horario(t(1793734200)))

    // Cripto é 24 h. Ao vivo só com dado recém-chegado; alguns ciclos sem chegar, só o horário; 2 min, dado velho.
    let btc = Cotacao(preco: 1, variacao: 0, moeda: "USD", em: t(1000), recebida: t(1000))
    #expect(btc.selo(agora: t(1030)) == .aoVivo)
    #expect(btc.selo(agora: t(1031)) == .horario(t(1000)))
    #expect(btc.selo(agora: t(1120)) == .horario(t(1000)))
    #expect(btc.selo(agora: t(1121)) == .velho(desde: t(1000)))
    #expect(!btc.velha(agora: t(1120)) && btc.velha(agora: t(1121)))
    // Parada com o mercado fechado também avisa: o app não sabe se o pregão de hoje já abriu.
    #expect(fechamento.selo(agora: t(1793741090 + 121)) == .velho(desde: t(1793741090)))
    // Fonte de atraso desconhecido: só o horário.
    var semAtraso = btc
    semAtraso.atraso = nil
    #expect(semAtraso.selo(agora: t(1001)) == .horario(t(1000)))
}

@Test func snapshotComUmCambioSo() throws {
    let agora = t(10_000)
    var fontes = Fontes()
    fontes.acoes["a:PETR4"] = Cotacao(preco: 50, variacao: 0.01, moeda: "BRL", recebida: agora)
    fontes.cripto["c:BTC"] = Cotacao(preco: 78_000, variacao: 0.015, moeda: "USD", recebida: agora)
    fontes.cambio["USD"] = Cotacao(preco: 5.5, variacao: 0.01, moeda: "BRL", recebida: agora - 60)
    fontes.cambio["EUR"] = Cotacao(preco: 6.1, variacao: 0, moeda: "BRL", recebida: agora - 180)  // parou há 3 min

    let s = Snapshot(fontes, agora: agora)
    #expect(s.em == agora)
    #expect(s.cambio == ["USD": 5.5])  // o euro velho não converte nada
    #expect(s.cambioEm == ["USD": agora - 60, "EUR": agora - 180])
    let btc = try #require(s.cotacoes["c:BTC"])
    #expect(btc.moeda == "BRL" && btc.preco == 78_000 * 5.5)
    #expect(btc.variacao == (1 + 0.015) * (1 + 0.01) - 1)
    #expect(btc.recebida == agora - 60)  // tem a idade do mais velho: o câmbio
    #expect(s.cotacoes["a:PETR4"]?.preco == 50)
    // BRL e USDT têm preço fixo: o real vale 1 real e o USDT, 1 dólar ao câmbio do momento. Constante não tem selo.
    #expect(s.cotacoes["c:BRL"]?.preco == 1 && s.cotacoes["c:BRL"]?.moeda == "BRL")
    #expect(s.cotacoes["c:BRL"]?.selo(agora: agora + 3600) == .fixo)
    let usdt = try #require(s.cotacoes["c:USDT"])
    #expect(usdt.preco == 5.5 && abs(usdt.variacao - 0.01) < 1e-12)  // a variação do próprio dólar
    #expect(usdt.selo(agora: agora) == .fixo && s.emDolar["c:USDT"]?.preco == 1)
    #expect(s.criptoSemCambio.isEmpty)
    // "Atualizado às" é o último dado da rede; os preços fixos não contam, para não parecer em dia sem internet.
    #expect(s.atualizado == agora)
    #expect(Snapshot(Fontes(), agora: agora).atualizado == nil)

    // Dólar velho: a cripto fica sem preço em reais em vez de misturar instantes; ações e o BRL seguem.
    let tarde = Snapshot(fontes, agora: agora + 61)
    #expect(tarde.cambio.isEmpty && tarde.cotacoes["c:BTC"] == nil && tarde.criptoSemCambio == ["c:BTC", "c:USDT"])
    #expect(tarde.cotacoes["c:BRL"] != nil && tarde.cotacoes["a:PETR4"] != nil)
    // Com a moeda escolhida em dólar, a cripto fica no dólar da Binance e não depende do câmbio; ação, na moeda dela.
    let bitcoin = Ativo(simbolo: "BTC", cripto: true)
    #expect(tarde.cotacao(bitcoin, moeda: "USD") == fontes.cripto["c:BTC"])
    #expect(tarde.cotacao(bitcoin, moeda: "BRL") == nil && s.cotacao(bitcoin, moeda: "EUR")?.moeda == "BRL")
    #expect(tarde.cotacao(Ativo(simbolo: "PETR4", cripto: false), moeda: "USD")?.moeda == "BRL")
    // Moeda sem par em USDT vem do par em reais: não precisa de câmbio nem entra no stream.
    var soReais = fontes
    soReais.cripto["c:XYZ"] = Cotacao(preco: 2, variacao: 0, moeda: "BRL", recebida: agora)
    let r = Snapshot(soReais, agora: agora + 61)
    #expect(r.cotacao(Ativo(simbolo: "XYZ", cripto: true), moeda: "USD")?.moeda == "BRL" && !r.criptoSemCambio.contains("c:XYZ"))

    // Câmbio da reserva (atraso desconhecido): a cripto convertida por ele não se diz "ao vivo".
    var reserva = fontes
    reserva.cambio["USD"]?.atraso = nil
    let convertida = try #require(Snapshot(reserva, agora: agora).cotacoes["c:BTC"])
    #expect(convertida.atraso == nil && convertida.selo(agora: agora) == .horario(convertida.em))

    // E sem câmbio o total que precisa dele não sai.
    let aapl = Linha(ativo: Ativo(simbolo: "AAPL", cripto: false), quantidade: 1, custo: nil, cotacao: Cotacao(preco: 300, variacao: 0, moeda: "USD"))
    #expect(somar([aapl], em: "BRL", cambio: tarde.cambio) == nil)
    #expect(somar([aapl], em: "BRL", cambio: s.cambio)?.patrimonio == 1650)

    // O BTC-BRL do Google às 17:38:50 é BTC-USD × USD-BRL, com os fechamentos anteriores das 00:00 UTC
    // (76.693,8075 × 5,4379 = 417.053,26): a mesma conta dá R$ 426.844,49 e +2,348%.
    let usdBRL = Cotacao(preco: 5.4939, variacao: 5.4939 / 5.4379 - 1, moeda: "BRL")
    let btcUSD = 426_844.49 / 5.4939
    let google = Cotacao(preco: btcUSD, variacao: btcUSD / 76_693.8075 - 1, moeda: "USD").emReais(usdBRL)
    #expect(abs(google.preco - 426_844.49) < 0.01)
    #expect(abs(google.variacao - 0.02348) < 0.00001)
}

@Test func filaJuntaOsTicks() {
    var fila = Fila<Double>()
    let agenda = [fila.receber(1, para: "c:BTC"), fila.receber(2, para: "c:BTC"), fila.receber(10, para: "c:ETH")]
    #expect(agenda == [true, false, false])  // só o primeiro agenda a publicação; os seguintes substituem
    #expect(fila.esvaziar() == ["c:BTC": 2, "c:ETH": 10])
    #expect(fila.pendentes.isEmpty)
    let deNovo = fila.receber(3, para: "c:BTC")
    #expect(deNovo)  // depois de publicar, agenda de novo
}

// Reserva do câmbio: resposta real da AwesomeAPI às 17:38:50 (dados de 17:34, o cache de até 5 min dela).
private let awesome = #"{"USDBRL":{"code":"USD","codein":"BRL","name":"Dólar Americano/Real Brasileiro","high":"5.512","low":"5.4366","varBid":"0.0573","pctChange":"1.053964","bid":"5.4939","ask":"5.4948","timestamp":"1793738087","create_date":"2026-11-03 17:34:47"},"EURBRL":{"code":"EUR","codein":"BRL","name":"Euro/Real Brasileiro","high":"6.1615","low":"6.0767","varBid":"0.0628","pctChange":"1.032015","bid":"6.148","ask":"6.15","timestamp":"1793738069","create_date":"2026-11-03 17:34:29"}}"#

@Test func cambioDaReserva() throws {
    let pares = try JSONDecoder().decode([String: CambioAwesome].self, from: Data(awesome.utf8))
    let c = CambioAwesome.cotacoes(pares, recebida: t(1793738330))
    let usd = try #require(c["USD"])
    #expect(usd.preco == 5.4939 && usd.moeda == "BRL" && abs(usd.variacao - 0.01053964) < 1e-12)  // desde 00:00 UTC, como o Yahoo
    #expect(usd.em == t(1793738087) && usd.recebida == t(1793738330) && usd.atraso == nil)
    #expect(c["EUR"]?.preco == 6.148 && c.count == 2)
    // Par estragado fica de fora em vez de virar câmbio zero.
    let ruim = try JSONDecoder().decode([String: CambioAwesome].self,
                                        from: Data(#"{"USDBRL":{"code":"USD","bid":"0","pctChange":"1","timestamp":"1"}}"#.utf8))
    #expect(CambioAwesome.cotacoes(ruim).isEmpty)
    // A Binance responde -1121 para par que não existe: é o que leva a cripto para o par em reais.
    #expect(ErroServico(code: -1121, msg: "Invalid symbol.").falha.codigo == -1121)
}

@Test func saldosDaBinanceSemCambio() throws {
    let agora = t(10_000)
    var fontes = Fontes()
    fontes.cripto["c:BTC"] = Cotacao(preco: 2000, variacao: 0.25, moeda: "USD", em: agora, recebida: agora)
    fontes.cripto["c:SHIB"] = Cotacao(preco: 0.0005, variacao: 0, moeda: "USD", em: agora, recebida: agora)
    let saldos = ["BTC": 0.5, "SHIB": 1000.0, "BRL": 50.0]  // SHIB vale US$ 0,50: poeira
    let precoMedio = ["BTC": 8000.0]                         // em reais

    // Yahoo e reserva fora do ar: o saldo segue na lista, com "sem câmbio", em vez de sumir como poeira.
    let s = Snapshot(fontes, agora: agora)
    let brl = linhasDeSaldo(saldos, precoMedio: precoMedio, snapshot: s, moeda: "BRL")
    #expect(brl.map(\.ativo.simbolo) == ["BTC", "BRL"])
    #expect(brl[0].cotacao == nil && s.faltaCambio(brl[0]) && !s.faltaCambio(brl[1]))
    #expect(cambiosEmFalta(brl, em: "BRL", snapshot: s) == ["USD"])

    // Em dólar a cripto tem preço sem câmbio; só o que está em reais (o saldo em BRL, o custo do BTC) pede câmbio.
    let usd = linhasDeSaldo(saldos, precoMedio: precoMedio, snapshot: s, moeda: "USD")
    #expect(usd.map(\.ativo.simbolo) == ["BTC", "BRL"])
    #expect(usd[0].cotacao?.moeda == "USD" && usd[0].valor == 1000 && usd[0].moedaCusto == "BRL" && !s.faltaCambio(usd[0]))
    #expect(cambiosEmFalta(usd, em: "USD", snapshot: s) == ["BRL"])
    // A linha mostra o valor em dólar; o resultado, que precisa do custo em reais, espera o câmbio.
    let linha = resumir(usd[0], em: "USD", cambio: s.cambio)
    #expect(linha.moeda == "USD" && linha.patrimonio == 1000 && linha.custo == 0)
    // Sem preço médio e sem saldo em reais, o total em dólar sai mesmo sem câmbio nenhum.
    let soBTC = linhasDeSaldo(["BTC": 0.5], precoMedio: [:], snapshot: s, moeda: "USD")
    #expect(cambiosEmFalta(soBTC, em: "USD", snapshot: s).isEmpty)
    #expect(somar(soBTC, em: "USD", cambio: s.cambio)?.patrimonio == 1000)

    // Com câmbio: em dólar, o custo em reais converte ao câmbio de agora e o "hoje" é o do BTC-USD.
    fontes.cambio["USD"] = Cotacao(preco: 5, variacao: 0.01, moeda: "BRL", em: agora, recebida: agora)
    let comCambio = Snapshot(fontes, agora: agora)
    let emDolar = try #require(somar(linhasDeSaldo(["BTC": 0.5], precoMedio: precoMedio, snapshot: comCambio, moeda: "USD"),
                                     em: "USD", cambio: comCambio.cambio))
    #expect(emDolar.patrimonio == 1000 && emDolar.custo == 800 && emDolar.hoje == 200)  // custo: 0,5 × 8.000 / 5
    // Em reais, BTC-USD × USD-BRL, como o BTC-BRL do Google; o resultado é o mesmo, convertido.
    let emReais = try #require(somar(linhasDeSaldo(["BTC": 0.5], precoMedio: precoMedio, snapshot: comCambio, moeda: "BRL"),
                                     em: "BRL", cambio: comCambio.cambio))
    #expect(emReais.patrimonio == 5000 && emReais.custo == 4000 && emReais.aberto.lucro == emDolar.aberto.lucro * 5)
}

@Test func esperaParaReconectar() {
    #expect(esperaReconexao(0) == .seconds(1))  // queda depois de muito tempo de pé, como no corte das 24 h
    #expect(esperaReconexao(1) == .seconds(2))
    #expect(esperaReconexao(3) == .seconds(8))
    #expect(esperaReconexao(6) == .seconds(60))
    #expect(esperaReconexao(500) == .seconds(60))
    #expect(esperaReconexao(-1) == .seconds(1))
    // Só recomeça a espera quem ficou de pé trazendo cotações; conexão muda que o vigia derrubou espera mais a cada vez.
    #expect(proximaTentativa(4, durou: 86_400, chegou: true) == 0)
    #expect(proximaTentativa(0, durou: 70, chegou: false) == 1)
    #expect(proximaTentativa(5, durou: 70, chegou: false) == 6)
    #expect(proximaTentativa(2, durou: 3, chegou: true) == 3)
}

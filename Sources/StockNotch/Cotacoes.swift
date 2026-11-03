import Foundation

// Uma cotação e a idade dela: o horário na fonte, quando chegou ao app, o atraso da fonte e o pregão.
struct Cotacao: Equatable {
    var preco: Double
    var variacao: Double             // fração (0.0123 = +1,23%), com o "dia" que o Google usa no mercado (ver Fonte)
    var moeda: String
    var em: Date = .now              // horário na fonte: regularMarketTime do Yahoo, evento da Binance
    var recebida: Date = .now        // quando chegou: é por ela que o dado fica velho
    var atraso: TimeInterval? = 0    // atraso da fonte (B3: 15 min); nil quando não se sabe
    var pregao: DateInterval? = nil  // sessão regular segundo o Yahoo; nil é mercado 24 h (cripto)
    var fixa = false                 // BRL e USDT: preço constante, sem idade a mostrar
}

// O que a tela diz sobre a idade de uma cotação.
enum Selo: Equatable {
    case aoVivo
    case atraso(TimeInterval)
    case fechado
    case velho(desde: Date)
    case horario(Date)  // atraso desconhecido, ou o horário da cotação não bate com ele: só o horário, sem prometer "ao vivo"
    case fixo           // preço constante (BRL, USDT): nada a dizer sobre a idade
}

extension Cotacao {
    static let prazo: TimeInterval = 120  // mais que isso sem chegar: dado velho, e câmbio velho não converte
    static let vivo: TimeInterval = 30    // folga sobre o atraso da fonte: "ao vivo" só com cotação de até 30 s

    func velha(agora: Date) -> Bool { agora.timeIntervalSince(recebida) > Self.prazo }

    // Aberto no horário que o dado mostra (agora − atraso). A grade do Yahoo pode estar errada (em 03/11/2026
    // dava a B3 até 17:00, e ela foi até 18:00): negócio bem depois do fim estende o pregão.
    // Sem negócio desde o início do pregão é feriado ou pré-abertura: fechado.
    func aberto(agora: Date) -> Bool {
        guard let pregao else { return true }
        let fim = em > pregao.end + 60 ? em + 300 : pregao.end
        return em >= pregao.start && agora - (atraso ?? 0) < fim
    }

    // Parada há mais de 2 min avisa mesmo com o mercado fechado: o app não sabe se o pregão de hoje já abriu.
    // "Ao vivo" e "15 min" só quando o horário da cotação confirma: chegar agora não basta, a fonte pode
    // devolver um preço congelado (ou o papel ficou sem negócio); aí o selo mostra o horário.
    func selo(agora: Date) -> Selo {
        if fixa { return .fixo }
        if velha(agora: agora) { return .velho(desde: recebida) }
        guard aberto(agora: agora) else { return .fechado }
        guard let atraso, agora.timeIntervalSince(em) <= atraso + Self.vivo else { return .horario(em) }
        return atraso > 0 ? .atraso(atraso) : .aoVivo
    }

    // Como o Google monta o BTC-BRL: BTC-USD × USD-BRL, com a variação das duas desde 00:00 UTC.
    // O preço em reais chega com o mais velho dos dois e tem o maior atraso (desconhecido com o câmbio da reserva).
    func emReais(_ dolar: Cotacao) -> Cotacao {
        var c = self
        c.preco = preco * dolar.preco
        c.variacao = (1 + variacao) * (1 + dolar.variacao) - 1
        c.moeda = "BRL"
        c.recebida = min(recebida, dolar.recebida)
        c.atraso = atraso.flatMap { a in dolar.atraso.map { max(a, $0) } }
        return c
    }
}

// O que chegou de cada fonte, como chegou. As telas não leem daqui: leem do Snapshot montado a partir disto.
struct Fontes {
    var acoes: [String: Cotacao] = [:]   // por ativo, na moeda dele (Yahoo)
    var cripto: [String: Cotacao] = [:]  // por ativo, em dólares (pares em USDT) ou em reais (moeda sem par em USDT)
    var cambio: [String: Cotacao] = [:]  // reais por dólar e por euro (Yahoo, ou a AwesomeAPI na falha dele)
    var series: [String: Serie] = [:]    // desenho do dia por ativo, buscado a cada 60 s (ver Grafico.swift)
    var serieDolar: [Ponto] = []         // reais por dólar ao longo do dia, para a cripto em reais
}

// Cotações e câmbio montados de uma vez, para todas as telas e todos os totais baterem entre si.
struct Snapshot {
    var cotacoes: [String: Cotacao] = [:]  // por ativo, na moeda dele; cripto já em reais
    var emDolar: [String: Cotacao] = [:]   // cripto em dólares, como veio: com a moeda escolhida em dólar, dispensa o câmbio
    var cambio: Cambio = [:]               // só o câmbio em dia
    var cambioEm: [String: Date] = [:]     // quando chegou cada câmbio, também o velho, para o aviso
    var criptoSemCambio: Set<String> = []  // cripto sem dólar em dia: fica sem preço em reais
    var em: Date?                          // quando foi montado: é o "agora" das regras de idade
    var atualizado: Date?                  // o último dado que chegou da rede (os preços fixos não contam)
    var series: [String: Serie] = [:]      // como veio da fonte; serie(_:ate:) ajusta à cotação mostrada
    var serieDolar: [Ponto] = []
}

extension Snapshot {
    // Uma taxa só por instante, e só em dia: cotação nova com câmbio velho não entra em preço nem em total.
    init(_ fontes: Fontes, agora: Date) {
        let emDia = fontes.cambio.filter { !$0.value.velha(agora: agora) }
        let todas = Array(fontes.acoes.values) + Array(fontes.cripto.values) + Array(fontes.cambio.values)
        self.init(cotacoes: fontes.acoes, cambio: emDia.mapValues(\.preco), cambioEm: fontes.cambio.mapValues(\.recebida),
                  em: agora, atualizado: todas.map(\.recebida).max(), series: fontes.series, serieDolar: fontes.serieDolar)
        var cripto = fontes.cripto
        for (moeda, emMoeda) in Fonte.fixas {
            cripto[Ativo(simbolo: moeda, cripto: true).id] = Cotacao(preco: 1, variacao: 0, moeda: emMoeda, em: agora, recebida: agora, fixa: true)
        }
        for (id, c) in cripto {
            if c.moeda == "BRL" {
                cotacoes[id] = c
                continue
            }
            emDolar[id] = c
            if let dolar = emDia["USD"] { cotacoes[id] = c.emReais(dolar) } else { criptoSemCambio.insert(id) }
        }
    }

    // Cripto em dólar quando é a moeda escolhida (como o BTC-USD do Google, sem depender do câmbio); senão, em reais.
    func cotacao(_ ativo: Ativo, moeda: String) -> Cotacao? {
        (ativo.cripto && moeda == "USD" ? emDolar[ativo.id] : nil) ?? cotacoes[ativo.id]
    }

    // Linha de cripto sem preço só porque falta o dólar em dia: a tela diz "sem câmbio" em vez de esconder.
    func faltaCambio(_ linha: Linha) -> Bool { linha.cotacao == nil && criptoSemCambio.contains(linha.ativo.id) }
}

// Resposta do chart do Yahoo: o meta (a cotação) e as barras (a série do minigráfico, ver Grafico.swift).
struct RespostaYahoo: Decodable {
    let chart: Chart
    struct Chart: Decodable { let result: [Item]? }
    struct Item: Decodable {
        let meta: Meta
        let timestamp: [TimeInterval]?
        let indicators: Indicadores?
    }
    struct Indicadores: Decodable { let quote: [Barras] }
    struct Barras: Decodable { let close: [Double?] }  // null na barra sem negócio
    struct Meta: Decodable {
        let regularMarketPrice: Double
        let previousClose: Double?
        let chartPreviousClose: Double
        let currency: String
        let regularMarketTime: TimeInterval?
        let exchangeName: String?
        let currentTradingPeriod: Grade?
        struct Grade: Decodable { let regular: Periodo }
        struct Periodo: Decodable { let start, end: TimeInterval }
    }

    // Atraso por bolsa no Yahoo (https://help.yahoo.com/kb/SLN2310.html): B3 15 min, igual ao Google;
    // ações dos EUA e câmbio em tempo real. Bolsa fora da lista fica com atraso desconhecido.
    static let atrasos: [String: TimeInterval] = ["SAO": 900, "NMS": 0, "NGM": 0, "NCM": 0, "NYQ": 0, "ASE": 0, "PCX": 0, "BTS": 0, "CCY": 0]

    // Variação do dia como no Google: contra o fechamento oficial anterior (B3: o do leilão; EUA: o da sessão
    // regular, já que pré e pós não entram no regularMarketPrice). No câmbio, Yahoo e Google fecham o dia
    // às 00:00 UTC, então o fechamento anterior é o preço dessa hora.
    func cotacao(recebida: Date = .now) throws -> Cotacao {
        guard let m = chart.result?.first?.meta else { throw URLError(.badServerResponse) }
        let anterior = m.previousClose ?? m.chartPreviousClose
        return Cotacao(preco: m.regularMarketPrice, variacao: anterior > 0 ? m.regularMarketPrice / anterior - 1 : 0, moeda: m.currency,
                       em: m.regularMarketTime.map(Date.init(timeIntervalSince1970:)) ?? recebida, recebida: recebida,
                       atraso: m.exchangeName.flatMap { Self.atrasos[$0] },
                       pregao: m.currentTradingPeriod.map { p in
                           DateInterval(start: Date(timeIntervalSince1970: p.regular.start),
                                        end: Date(timeIntervalSince1970: max(p.regular.start, p.regular.end)))
                       })
    }
}

enum Fonte {
    static func cotacao(_ ativo: Ativo) async throws -> Cotacao {
        ativo.cripto ? try await cripto(ativo.simbolo) : try await yahoo(ativo.simboloYahoo)
    }

    // Reais por dólar e por euro, do mesmo endpoint das ações. Se o Yahoo falhar, a AwesomeAPI cobre (a cripto também
    // depende do dólar); o que falhar nas duas fica de fora, e o último bom envelhece.
    static func cambio() async -> [String: Cotacao] {
        async let usd = try? yahoo("USDBRL=X")
        async let eur = try? yahoo("EURBRL=X")
        let yahoo = ["USD": await usd, "EUR": await eur].compactMapValues { $0 }
        guard yahoo.count < 2 else { return yahoo }
        let reserva: [String: CambioAwesome]? = try? await baixar("https://economia.awesomeapi.com.br/json/last/USD-BRL,EUR-BRL")
        return CambioAwesome.cotacoes(reserva ?? [:]).merging(yahoo) { $1 }
    }

    // API pública não oficial do Yahoo, sem chave. B3 com 15 min de atraso (tempo real da B3 só pago).
    static func chart(_ simbolo: String, _ consulta: String = "range=1d") async throws -> RespostaYahoo {
        let caminho = simbolo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? simbolo
        return try await baixar("https://query1.finance.yahoo.com/v8/finance/chart/\(caminho)?\(consulta)")
    }

    private static func yahoo(_ simbolo: String) async throws -> Cotacao { try await chart(simbolo).cotacao() }

    // Moedas de preço fixo, sem fonte, e a moeda em que valem 1: o real, e o USDT, que vale como dólar
    // (como em todos os pares em USDT, embora fique ~0,15% acima dele).
    static let fixas = ["BRL": "BRL", "USDT": "USD"]

    // Reserva do stream (e a primeira cotação): o mesmo par em USDT e o mesmo dia. Moeda sem par em USDT (a Binance
    // responde -1121, símbolo inválido) vem do par em reais, que fica fora do stream.
    private static func cripto(_ moeda: String) async throws -> Cotacao {
        do {
            return try await diaBinance(moeda + "USDT", moeda: "USD")
        } catch let erro as Falha where erro.codigo == -1121 {
            return try await diaBinance(moeda + "BRL", moeda: "BRL")
        }
    }

    // Dia de cripto como no Google: desde 00:00 UTC, não as últimas 24 h; o tradingDay com timeZone=0 dá a abertura dele.
    private static func diaBinance(_ par: String, moeda: String) async throws -> Cotacao {
        struct Resposta: Decodable { let lastPrice, openPrice: String }
        let r: Resposta = try await baixar("https://api.binance.com/api/v3/ticker/tradingDay?symbol=\(par)&timeZone=0")
        guard let ultimo = Double(r.lastPrice), let abertura = Double(r.openPrice) else { throw URLError(.cannotParseResponse) }
        return Cotacao(preco: ultimo, variacao: abertura > 0 ? ultimo / abertura - 1 : 0, moeda: moeda)
    }
}

// Um par da AwesomeAPI (reserva do câmbio): {"USDBRL": {"code": "USD", "bid": "5.4939", "pctChange": "1.05", "timestamp": "..."}}.
// Mesma origem e mesmo dia do Yahoo (variação desde 00:00 UTC), mas em cache de até 5 min: atraso desconhecido.
struct CambioAwesome: Decodable {
    let code, bid, pctChange, timestamp: String

    static func cotacoes(_ pares: [String: CambioAwesome], recebida: Date = .now) -> [String: Cotacao] {
        var r: [String: Cotacao] = [:]
        for p in pares.values {
            guard let preco = Double(p.bid), preco > 0, let pct = Double(p.pctChange), let t = TimeInterval(p.timestamp) else { continue }
            r[p.code] = Cotacao(preco: preco, variacao: pct / 100, moeda: "BRL", em: Date(timeIntervalSince1970: t), recebida: recebida, atraso: nil)
        }
        return r
    }
}

func baixar<T: Decodable>(_ endereco: String) async throws -> T {
    guard let url = URL(string: endereco) else { throw URLError(.badURL) }
    return try await baixar(URLRequest(url: url))
}

func baixar<T: Decodable>(_ pedido: URLRequest) async throws -> T {
    var req = pedido
    req.cachePolicy = .reloadIgnoringLocalCacheData
    req.timeoutInterval = 10
    req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")  // o Yahoo responde 429 para alguns User-Agents
    let (data, resposta) = try await URLSession.shared.data(for: req)
    guard (resposta as? HTTPURLResponse)?.statusCode == 200 else {
        if let erro = try? JSONDecoder().decode(ErroServico.self, from: data) { throw erro.falha }
        throw Falha("O serviço de cotações respondeu com erro.", "The quote service returned an error.")
    }
    return try JSONDecoder().decode(T.self, from: data)
}

// A Binance explica a recusa em {"code": -2015, "msg": "..."}, só em inglês: os casos comuns ganham texto nos dois idiomas.
struct ErroServico: Decodable {
    let code: Int?
    let msg: String

    var falha: Falha {
        switch code {
        case -2008, -2014, -2015:
            Falha("Chave recusada: confira a API Key, a Secret Key e as restrições de IP.",
                  "Key refused: check the API Key, the Secret Key and the IP restrictions.")
        case -1022:
            Falha("Assinatura recusada: confira a Secret Key.", "Signature refused: check the Secret Key.")
        case -1003:
            Falha("Pedidos demais; tente de novo em alguns minutos.", "Too many requests; try again in a few minutes.")
        default:
            Falha("Pedido recusado: \(msg)", "Request refused: \(msg)", codigo: code)
        }
    }
}

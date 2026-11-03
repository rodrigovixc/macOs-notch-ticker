import Charts
import SwiftUI

// Minigráfico do dia: a série intradiária de cada ativo, buscada a cada 60 s (o desenho muda devagar, e o Yahoo
// limita pedidos), ajustada para terminar no preço que a tela mostra.

struct Ponto: Equatable {
    var em: Date
    var preco: Double
}

// Pontos em ordem de horário, na moeda da fonte: ação na dela, cripto em dólar (par em USDT) ou do par em reais.
struct Serie: Equatable {
    var moeda: String
    var pontos: [Ponto]
}

// O dia da cripto (e do câmbio) começa às 00:00 UTC, como a variação que o app e o Google mostram.
let calendarioUTC: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = .gmt
    return c
}()

extension Cotacao {
    // Contra o que a variação do dia é medida: o fechamento anterior (cripto: o preço das 00:00 UTC).
    // Tirado da própria cotação, o tracejado e a cor nunca discordam da variação mostrada.
    var referencia: Double { preco / (1 + variacao) }

    // Começo do dia que a cotação mostra: o pregão do último negócio, ou 00:00 UTC no mercado de 24 h.
    // Antes da abertura o negócio é do pregão anterior, cujo início o Yahoo não diz: sem limite.
    var inicioDoDia: Date {
        guard let pregao else { return calendarioUTC.startOfDay(for: em) }
        return em >= pregao.start ? pregao.start : .distantPast
    }
}

// Termina na cotação mostrada: a série (de até 60 s atrás) ganha o preço atual como último ponto, e o que for
// posterior a ele (a vela em curso da Binance, que fecha no futuro) ou de outro dia (série buscada antes de o
// dia virar) sai.
func ajustar(_ pontos: [Ponto], a c: Cotacao) -> [Ponto] {
    let inicio = c.inicioDoDia
    return pontos.filter { $0.em >= inicio && $0.em < c.em } + [Ponto(em: c.em, preco: c.preco)]
}

// Cripto em reais ponto a ponto, como o preço dela: dólar × o câmbio daquele momento (o último até ali;
// antes do primeiro, o primeiro). Sem a série do dólar não há como converter.
func emReais(_ pontos: [Ponto], dolar: [Ponto]) -> [Ponto] {
    guard !dolar.isEmpty else { return [] }
    var i = 0
    return pontos.map { p in
        while i + 1 < dolar.count, dolar[i + 1].em <= p.em { i += 1 }
        return Ponto(em: p.em, preco: p.preco * dolar[i].preco)
    }
}

extension Snapshot {
    // O desenho do dia terminando na cotação que a linha mostra. nil sem série, com preço fixo (BRL, USDT)
    // ou sem dois pontos para traçar.
    func serie(_ ativo: Ativo, ate c: Cotacao) -> [Ponto]? {
        guard !c.fixa, let s = series[ativo.id] else { return nil }
        let pontos = s.moeda == c.moeda ? s.pontos : s.moeda == "USD" && c.moeda == "BRL" ? emReais(s.pontos, dolar: serieDolar) : []
        let ajustados = ajustar(pontos, a: c)
        return ajustados.count > 1 ? ajustados : nil
    }
}

extension RespostaYahoo {
    // Barras de 5 min do dia: o fechamento de cada uma no horário dela. Barra sem negócio (null) fica de fora.
    func serie() throws -> Serie {
        guard let item = chart.result?.first else { throw URLError(.badServerResponse) }
        let fechamentos = item.indicators?.quote.first?.close ?? []
        let pontos = zip(item.timestamp ?? [], fechamentos).compactMap { t, preco in
            preco.flatMap { $0 > 0 ? Ponto(em: Date(timeIntervalSince1970: t), preco: $0) : nil }
        }
        return Serie(moeda: item.meta.currency, pontos: pontos)
    }
}

// Vela da Binance: [início, "abertura", "máxima", "mínima", "fechamento", "volume", fim, ...], horários em ms.
struct VelaBinance: Decodable {
    let inicio, fim: Date
    let abertura, fechamento: Double

    init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let inicio = try c.decode(Double.self)
        let abertura = try c.decode(String.self)
        _ = try c.decode(String.self)
        _ = try c.decode(String.self)
        let fechamento = try c.decode(String.self)
        _ = try c.decode(String.self)
        let fim = try c.decode(Double.self)
        guard let a = Double(abertura), let f = Double(fechamento), a > 0, f > 0 else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "preço da vela")
        }
        self.inicio = Date(timeIntervalSince1970: inicio / 1000)
        self.fim = Date(timeIntervalSince1970: fim / 1000)
        self.abertura = a
        self.fechamento = f
    }
}

extension Serie {
    // A abertura das 00:00 UTC (a referência da variação: a linha sai do tracejado) e o fechamento de cada
    // vela no fim dela. A vela em curso fecha no futuro: o ajuste a troca pela cotação.
    init(velas: [VelaBinance], moeda: String) {
        let abertura = velas.first.map { [Ponto(em: $0.inicio, preco: $0.abertura)] } ?? []
        self.init(moeda: moeda, pontos: abertura + velas.map { Ponto(em: $0.fim, preco: $0.fechamento) })
    }
}

extension Fonte {
    // Ação (e câmbio) pelo mesmo chart do Yahoo, em barras de 5 min; cripto pelas velas da Binance no par da
    // cotação: o em reais, ou o em USDT, que a tela converte com a série do dólar.
    static func serie(_ ativo: Ativo, emReais: Bool) async throws -> Serie {
        guard ativo.cripto else { return try await serieYahoo(ativo.simboloYahoo) }
        return try await velas(ativo.simbolo + (emReais ? "BRL" : "USDT"), moeda: emReais ? "BRL" : "USD")
    }

    static func serieYahoo(_ simbolo: String) async throws -> Serie {
        try await chart(simbolo, "interval=5m&range=1d").serie()
    }

    // Velas de 15 min desde 00:00 UTC: 96 cobrem o dia inteiro.
    private static func velas(_ par: String, moeda: String) async throws -> Serie {
        let inicio = Int(calendarioUTC.startOfDay(for: .now).timeIntervalSince1970 * 1000)
        let velas: [VelaBinance] = try await baixar("https://api.binance.com/api/v3/klines?symbol=\(par)&interval=15m&startTime=\(inicio)&limit=96")
        return Serie(velas: velas, moeda: moeda)
    }
}

// Linha fina sem eixos, verde ou vermelha pela variação do dia, e o tracejado na referência dela. Decorativo para o
// VoiceOver: a linha da tabela e do notch já diz preço e variação em número. O espaço fica reservado sem série,
// para as colunas alinharem.
struct MiniGrafico: View {
    let pontos: [Ponto]?
    let cotacao: Cotacao?
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento
    @State private var desenhado = false

    var body: some View {
        ZStack {
            if let pontos, let cotacao, let primeiro = pontos.first, let ultimo = pontos.last {
                let referencia = cotacao.referencia
                let precos = pontos.map(\.preco) + [referencia]
                let menor = precos.min() ?? referencia, maior = precos.max() ?? referencia
                // Folga para o traço não ser cortado nas bordas; linha reta ganha uma faixa em volta.
                let folga = maior > menor ? (maior - menor) * 0.08 : max(abs(maior) * 0.001, 1e-9)
                Chart {
                    RuleMark(y: .value("Referência", referencia))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                    ForEach(pontos, id: \.em) { p in
                        LineMark(x: .value("Hora", p.em), y: .value("Preço", p.preco))
                            .lineStyle(StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(cor(cotacao.variacao))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .chartXScale(domain: primeiro.em...ultimo.em)
                .chartYScale(domain: (menor - folga)...(maior + folga))
                // Traça da esquerda para a direita ao aparecer; com Reduzir Movimento aparece pronto.
                .mask(alignment: .leading) {
                    Rectangle().scaleEffect(x: desenhado ? 1 : 0, anchor: .leading)
                }
            }
        }
        .frame(width: 56, height: 20)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(reduzirMovimento ? nil : .easeOut(duration: 0.5)) { desenhado = true }
        }
    }
}

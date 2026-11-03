import Foundation
import Observation

struct Compra: Codable, Identifiable, Hashable {
    var id = UUID()
    var quantidade: Double
    var preco: Double
    var data: Date
}

struct Ativo: Codable, Identifiable {
    var simbolo: String
    var cripto: Bool
    var compras: [Compra] = []
    var id: String { (cripto ? "c:" : "a:") + simbolo }

    var quantidade: Double { compras.reduce(0) { $0 + $1.quantidade } }
    var custo: Double { compras.reduce(0) { $0 + $1.quantidade * $1.preco } }

    // PETR4 → PETR4.SA: ticker da B3 termina em número e o Yahoo pede o sufixo.
    var simboloYahoo: String {
        let b3 = simbolo.last?.isNumber == true && !simbolo.contains(".")
        return b3 ? simbolo + ".SA" : simbolo
    }

    static func normalizar(_ texto: String, cripto: Bool) -> String {
        let s = texto.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || (!cripto && ".-^".contains($0))) }
        // "BTCBRL" vira "BTC": o par em reais é montado na busca da cotação.
        return cripto && s.count > 3 && s.hasSuffix("BRL") ? String(s.dropLast(3)) : s
    }
}

struct Cotacao {
    var preco: Double
    var variacao: Double  // fração: 0.0123 = +1,23%
    var moeda: String
}

struct Resultado {
    var lucro: Double
    var percentual: Double
}

func resultado(custo: Double, valor: Double) -> Resultado {
    Resultado(lucro: valor - custo, percentual: custo > 0 ? (valor - custo) / custo : 0)
}

// Uma linha do notch ou do painel: ativo manual (com custo) ou saldo da Binance (custo nil).
struct Linha: Identifiable {
    let ativo: Ativo
    let quantidade: Double
    let custo: Double?
    let cotacao: Cotacao?
    var id: String { (custo == nil ? "binance:" : "") + ativo.id }
    var valor: Double? { cotacao.map { $0.preco * quantidade } }
}

struct Total {
    var moeda: String
    var patrimonio = 0.0
    var hoje = 0.0
    var custo = 0.0
    var valorComCusto = 0.0

    var hojePct: Double { patrimonio - hoje > 0 ? hoje / (patrimonio - hoje) : 0 }
    var lucro: Resultado { resultado(custo: custo, valor: valorComCusto) }
}

// Um total por moeda: B3 e cripto em BRL, EUA em USD. Lucro só conta o que tem compra registrada.
func somar(_ linhas: [Linha]) -> [Total] {
    var totais: [String: Total] = [:]
    for linha in linhas where linha.quantidade > 0 {
        guard let c = linha.cotacao else { continue }
        let valor = linha.quantidade * c.preco
        var t = totais[c.moeda] ?? Total(moeda: c.moeda)
        t.patrimonio += valor
        t.hoje += valor - valor / (1 + c.variacao)
        if let custo = linha.custo {
            t.custo += custo
            t.valorComCusto += valor
        }
        totais[c.moeda] = t
    }
    return totais.values.sorted { $0.moeda < $1.moeda }
}

// Aceita "1.234,56", "0,5" e "0.5".
func numero(_ texto: String) -> Double? {
    let t = texto.trimmingCharacters(in: .whitespaces)
    return Double(t.contains(",") ? t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") : t)
}

@MainActor @Observable
final class Carteira {
    private(set) var ativos: [Ativo] = []
    private(set) var cotacoes: [String: Cotacao] = [:]
    private(set) var falhas: Set<String> = []
    private(set) var erroArquivo: String?
    private(set) var atualizadoEm: Date?
    private(set) var saldosBinance: [String: Double] = [:]
    private(set) var erroBinance: String?
    private var credencial: Credencial? = Chaveiro.ler()

    // JSON legível, dá pra fazer backup ou editar à mão
    let arquivo = URL.applicationSupportDirectory.appending(path: "StockNotch/carteira.json")

    var binanceConectada: Bool { credencial != nil }

    var linhas: [Linha] {
        ativos.map { Linha(ativo: $0, quantidade: $0.quantidade, custo: $0.custo, cotacao: cotacoes[$0.id]) }
    }

    var linhasBinance: [Linha] {
        saldosBinance
            .map { moeda, qtd in
                let ativo = Ativo(simbolo: moeda, cripto: true)
                return Linha(ativo: ativo, quantidade: qtd, custo: nil, cotacao: cotacoes[ativo.id])
            }
            .filter { ($0.valor ?? 0) >= 1 }  // esconde poeira abaixo de R$ 1
            .sorted { ($0.valor ?? 0) > ($1.valor ?? 0) }
    }

    var totais: [Total] { somar(linhas + linhasBinance) }

    var simbolosSemCotacao: [String] { ativos.filter { falhas.contains($0.id) }.map(\.simbolo) }

    init() {
        guard let data = try? Data(contentsOf: arquivo) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            ativos = try decoder.decode([Ativo].self, from: data)
        } catch {
            // Não sobrescreve um arquivo que não conseguiu ler.
            erroArquivo = "Não consegui ler \(arquivo.path). Nada será salvo até corrigir."
        }
    }

    func adicionar(simbolo: String, cripto: Bool, compra: Compra?) {
        let novo = Ativo(simbolo: simbolo, cripto: cripto, compras: compra.map { [$0] } ?? [])
        if let i = ativos.firstIndex(where: { $0.id == novo.id }) {
            if let compra { ativos[i].compras.append(compra) }
        } else {
            ativos.append(novo)
        }
        salvar()
        Task { await atualizar() }
    }

    func remover(_ ativo: Ativo) {
        ativos.removeAll { $0.id == ativo.id }
        cotacoes[ativo.id] = nil
        salvar()
    }

    func remover(_ compra: Compra, de ativo: Ativo) {
        guard let i = ativos.firstIndex(where: { $0.id == ativo.id }) else { return }
        ativos[i].compras.removeAll { $0.id == compra.id }
        salvar()
    }

    func conectarBinance(chave: String, segredo: String) async throws {
        let cred = Credencial(chave: chave.trimmingCharacters(in: .whitespacesAndNewlines),
                              segredo: segredo.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !cred.chave.isEmpty, !cred.segredo.isEmpty,
              (cred.chave + cred.segredo).allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { throw Falha("Cole a API Key e a Secret Key exatamente como a Binance mostrou.") }
        try await Binance.verificar(cred)
        try Chaveiro.salvar(cred)
        credencial = cred
        await atualizar()
    }

    func desconectarBinance() {
        Chaveiro.apagar()
        credencial = nil
        saldosBinance = [:]
        erroBinance = nil
    }

    func atualizar() async {
        if let credencial {
            do {
                let saldos = try await Binance.saldos(credencial)
                if self.credencial != nil { saldosBinance = saldos }
                erroBinance = nil
            } catch {
                erroBinance = error.localizedDescription
            }
        }
        var lista = ativos
        for moeda in saldosBinance.keys where !lista.contains(where: { $0.id == "c:" + moeda }) {
            lista.append(Ativo(simbolo: moeda, cripto: true))
        }
        let resultados = await withTaskGroup(of: (String, Cotacao?).self) { grupo in
            for ativo in lista { grupo.addTask { (ativo.id, try? await Fonte.cotacao(ativo)) } }
            var r: [(String, Cotacao?)] = []
            for await item in grupo { r.append(item) }
            return r
        }
        for (id, cotacao) in resultados where cotacao != nil { cotacoes[id] = cotacao }
        // Só avisa dos ativos manuais; moeda da Binance sem cotação só some da lista.
        falhas = Set(resultados.filter { $0.1 == nil }.map(\.0)).intersection(ativos.map(\.id))
        atualizadoEm = .now
    }

    private func salvar() {
        guard erroArquivo == nil else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(at: arquivo.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(ativos).write(to: arquivo, options: .atomic)
        } catch {
            erroArquivo = "Erro ao salvar: \(error.localizedDescription)"
        }
    }
}

struct Falha: LocalizedError {
    let errorDescription: String?
    init(_ mensagem: String) { errorDescription = mensagem }
}

enum Fonte {
    static func cotacao(_ ativo: Ativo) async throws -> Cotacao {
        ativo.cripto ? try await cripto(ativo.simbolo) : try await yahoo(ativo.simboloYahoo)
    }

    // API pública não oficial do Yahoo, sem chave: B3 vem com ~15 min de atraso (tempo real da B3 só pago)
    private static func yahoo(_ simbolo: String) async throws -> Cotacao {
        struct Resposta: Decodable {
            let chart: Chart
            struct Chart: Decodable { let result: [Item]? }
            struct Item: Decodable { let meta: Meta }
            struct Meta: Decodable {
                let regularMarketPrice: Double
                let chartPreviousClose: Double
                let currency: String
            }
        }
        let caminho = simbolo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? simbolo
        let r: Resposta = try await baixar("https://query1.finance.yahoo.com/v8/finance/chart/\(caminho)?range=1d")
        guard let m = r.chart.result?.first?.meta else { throw URLError(.badServerResponse) }
        return Cotacao(preco: m.regularMarketPrice, variacao: m.regularMarketPrice / m.chartPreviousClose - 1, moeda: m.currency)
    }

    private static func cripto(_ moeda: String) async throws -> Cotacao {
        if moeda == "BRL" { return Cotacao(preco: 1, variacao: 0, moeda: "BRL") }
        if let direto = try? await ticker(moeda + "BRL") {
            return Cotacao(preco: direto.preco, variacao: direto.variacao, moeda: "BRL")
        }
        // Sem par em reais na Binance: converte pelo USDT. A variação é a do par em USDT.
        let emUSDT = try await ticker(moeda + "USDT")
        let dolar = try await ticker("USDTBRL")
        return Cotacao(preco: emUSDT.preco * dolar.preco, variacao: emUSDT.variacao, moeda: "BRL")
    }

    // Variação das últimas 24 h, como é o costume em cripto.
    private static func ticker(_ par: String) async throws -> (preco: Double, variacao: Double) {
        struct Resposta: Decodable {
            let lastPrice: String
            let priceChangePercent: String
        }
        let r: Resposta = try await baixar("https://api.binance.com/api/v3/ticker/24hr?symbol=\(par)")
        guard let preco = Double(r.lastPrice), let pct = Double(r.priceChangePercent) else { throw URLError(.cannotParseResponse) }
        return (preco, pct / 100)
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
        throw Falha((try? JSONDecoder().decode(ErroServico.self, from: data))?.msg ?? "O serviço de cotações respondeu com erro.")
    }
    return try JSONDecoder().decode(T.self, from: data)
}

// A Binance explica a recusa em {"msg": "..."}.
private struct ErroServico: Decodable { let msg: String }

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

    // Moeda até a primeira cotação chegar (depois vale a do Yahoo): B3 e cripto em reais, o resto em dólar.
    var moedaPrevista: String { cripto || simboloYahoo.hasSuffix(".SA") ? "BRL" : "USD" }

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
    var moeda: String { cotacao?.moeda ?? ativo.moedaPrevista }
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

// Quantos reais vale 1 unidade de cada moeda (o real é o pivô), ex.: ["USD": 5.4, "EUR": 6.2].
typealias Cambio = [String: Double]

// Converte passando pelo real. nil se faltar o câmbio de uma das moedas: melhor nada do que um número errado.
func converter(_ valor: Double, de origem: String, para destino: String, cambio: Cambio) -> Double? {
    if origem == destino { return valor }
    let reais = { (moeda: String) in moeda == "BRL" ? 1 : cambio[moeda] }
    guard let a = reais(origem), let b = reais(destino), a > 0, b > 0 else { return nil }
    return valor * a / b
}

// Um total só, na moeda escolhida. Lucro só conta o que tem compra registrada.
// nil quando falta câmbio para alguma posição: um total sem ela estaria errado.
func somar(_ linhas: [Linha], em moeda: String, cambio: Cambio) -> Total? {
    var t = Total(moeda: moeda)
    for linha in linhas where linha.quantidade > 0 {
        guard let c = linha.cotacao else { continue }
        guard let valor = converter(linha.quantidade * c.preco, de: c.moeda, para: moeda, cambio: cambio),
              let custo = converter(linha.custo ?? 0, de: c.moeda, para: moeda, cambio: cambio)
        else { return nil }
        t.patrimonio += valor
        t.hoje += valor - valor / (1 + c.variacao)
        if linha.custo != nil {
            t.custo += custo
            t.valorComCusto += valor
        }
    }
    return t
}

// Cotações e câmbio buscados no mesmo ciclo e publicados de uma vez, para todas as telas baterem entre si.
// Quem falhou no ciclo mantém o último valor bom, para não piscar.
struct Snapshot {
    var cotacoes: [String: Cotacao] = [:]
    var cambio: Cambio = [:]
    var cambioEm: [String: Date] = [:]
    var falhas: Set<String> = []
    var em: Date?

    // Câmbio guardado de ciclos anteriores porque o Yahoo falhou: passado de 5 min, a tela avisa desde quando.
    func cambioVelho(_ moedas: Set<String>) -> Date? {
        guard let em, let antigo = moedas.compactMap({ cambioEm[$0] }).min(), em.timeIntervalSince(antigo) > 300 else { return nil }
        return antigo
    }
}

// Em português aceita "1.234,56", "0,5" e "0.5"; em inglês a vírgula separa milhar: "1,234.56".
func numero(_ texto: String, idioma: Idioma = .pt) -> Double? {
    let t = texto.trimmingCharacters(in: .whitespaces)
    if idioma == .en {
        // "32,50" ou "0,5" é vírgula decimal: nil para o form avisar, em vez de gravar 3250 ou 5.
        guard !t.contains(",") || t.wholeMatch(of: #/\d{1,3}(,\d{3})*(\.\d+)?/#) != nil else { return nil }
        return Double(t.replacingOccurrences(of: ",", with: ""))
    }
    return Double(t.contains(",") ? t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") : t)
}

@MainActor @Observable
final class Carteira {
    private(set) var ativos: [Ativo] = []
    private(set) var snapshot = Snapshot()
    private(set) var erroArquivo: Falha?
    private(set) var saldosBinance: [String: Double] = [:]
    private(set) var erroBinance: (any Error)?
    private var credencial: Credencial? = Chaveiro.ler()

    // JSON legível, dá pra fazer backup ou editar à mão
    let arquivo = URL.applicationSupportDirectory.appending(path: "StockNotch/carteira.json")

    var binanceConectada: Bool { credencial != nil }
    var cotacoes: [String: Cotacao] { snapshot.cotacoes }
    var falhas: Set<String> { snapshot.falhas }
    var atualizadoEm: Date? { snapshot.em }

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

    // Preço fica na moeda do ativo; valor, resultado e totais vão para a moeda escolhida nos Ajustes.
    var moeda: String { Ajustes.atual.moeda.rawValue }

    var total: Total? { somar(linhas + linhasBinance, em: moeda, cambio: snapshot.cambio) }

    // Moedas de posições que não dá para converter agora; com alguma, o total fica indisponível.
    var semCambio: [String] {
        moedasConvertidas.filter { converter(1, de: $0, para: moeda, cambio: snapshot.cambio) == nil }.sorted()
    }

    // Horário do câmbio mais antigo em uso, quando ficou para trás das cotações.
    var cambioVelho: Date? {
        let usadas = moedasConvertidas.isEmpty ? [] : moedasConvertidas.union([moeda]).subtracting(["BRL"])
        return snapshot.cambioVelho(usadas)
    }

    // Moedas das posições com cotação que precisam de câmbio para a moeda escolhida.
    private var moedasConvertidas: Set<String> {
        Set((linhas + linhasBinance).filter { $0.quantidade > 0 }.compactMap { $0.cotacao?.moeda }).subtracting([moeda])
    }

    // Sem câmbio, o valor fica na moeda do ativo (e com o símbolo dela): nunca convertido errado.
    func convertido(_ valor: Double, de origem: String) -> (valor: Double, moeda: String) {
        converter(valor, de: origem, para: moeda, cambio: snapshot.cambio).map { ($0, moeda) } ?? (valor, origem)
    }

    // O percentual não muda com o câmbio, só o valor do lucro.
    func lucro(_ linha: Linha) -> (resultado: Resultado, moeda: String)? {
        guard let c = linha.cotacao, let custo = linha.custo, linha.quantidade > 0 else { return nil }
        let r = resultado(custo: custo, valor: linha.quantidade * c.preco)
        let lucro = convertido(r.lucro, de: c.moeda)
        return (Resultado(lucro: lucro.valor, percentual: r.percentual), lucro.moeda)
    }

    var simbolosSemCotacao: [String] { ativos.filter { falhas.contains($0.id) }.map(\.simbolo) }

    init() {
        guard let data = try? Data(contentsOf: arquivo) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            ativos = try decoder.decode([Ativo].self, from: data)
        } catch {
            // Não sobrescreve um arquivo que não conseguiu ler.
            erroArquivo = Falha("Não consegui ler \(arquivo.path). Nada será salvo até corrigir.",
                                "Couldn't read \(arquivo.path). Nothing will be saved until it's fixed.")
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
        snapshot.cotacoes[ativo.id] = nil
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
        else { throw Falha("Cole a API Key e a Secret Key exatamente como a Binance mostrou.",
                           "Paste the API Key and Secret Key exactly as Binance shows them.") }
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
                erroBinance = error
            }
        }
        var lista = ativos
        for moeda in saldosBinance.keys where !lista.contains(where: { $0.id == "c:" + moeda }) {
            lista.append(Ativo(simbolo: moeda, cripto: true))
        }
        async let cambio = Fonte.cambio()
        let resultados = await withTaskGroup(of: (String, Cotacao?).self) { grupo in
            for ativo in lista { grupo.addTask { (ativo.id, try? await Fonte.cotacao(ativo)) } }
            var r: [(String, Cotacao?)] = []
            for await item in grupo { r.append(item) }
            return r
        }
        let novoCambio = await cambio
        // Monta depois do último await, sobre o snapshot mais recente, e troca de uma vez.
        var novo = snapshot
        for (id, cotacao) in resultados { if let cotacao { novo.cotacoes[id] = cotacao } }
        novo.cambio.merge(novoCambio) { $1 }
        for moeda in novoCambio.keys { novo.cambioEm[moeda] = .now }
        // Só avisa dos ativos manuais; moeda da Binance sem cotação só some da lista.
        novo.falhas = Set(resultados.filter { $0.1 == nil }.map(\.0)).intersection(ativos.map(\.id))
        novo.em = .now
        snapshot = novo
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
            // Só o código do erro: o texto do sistema viria no idioma em que o app abriu.
            let codigo = (error as NSError).code
            erroArquivo = Falha("Não consegui salvar \(arquivo.path) (erro \(codigo)).", "Couldn't save \(arquivo.path) (error \(codigo)).")
        }
    }
}

// Texto nos dois idiomas; mensagem(_:) escolhe na hora de mostrar.
struct Falha: Error {
    let pt: String
    let en: String
    init(_ pt: String, _ en: String) {
        self.pt = pt
        self.en = en
    }
}

enum Fonte {
    static func cotacao(_ ativo: Ativo) async throws -> Cotacao {
        ativo.cripto ? try await cripto(ativo.simbolo) : try await yahoo(ativo.simboloYahoo)
    }

    // Câmbio do dólar e do euro em reais, do mesmo endpoint das ações. O que falhar fica de fora.
    static func cambio() async -> Cambio {
        async let usd = try? yahoo("USDBRL=X")
        async let eur = try? yahoo("EURBRL=X")
        return ["USD": await usd?.preco, "EUR": await eur?.preco].compactMapValues { $0 }
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
            Falha("Pedido recusado: \(msg)", "Request refused: \(msg)")
        }
    }
}

import Foundation
import Observation

struct Ativo: Codable, Identifiable, Equatable {
    var simbolo: String
    var cripto: Bool
    var compras: [Operacao] = []
    var vendas: [Operacao] = []
    var alertas: [Alerta] = []
    var id: String { (cripto ? "c:" : "a:") + simbolo }

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

extension Ativo {
    // Campos novos são opcionais no JSON: o carteira.json de antes das vendas e dos alertas continua legível.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        simbolo = try c.decode(String.self, forKey: .simbolo)
        cripto = try c.decode(Bool.self, forKey: .cripto)
        compras = try c.decodeIfPresent([Operacao].self, forKey: .compras) ?? []
        vendas = try c.decodeIfPresent([Operacao].self, forKey: .vendas) ?? []
        alertas = try c.decodeIfPresent([Alerta].self, forKey: .alertas) ?? []
    }
}

struct Resultado {
    var lucro: Double
    var percentual: Double
}

func resultado(custo: Double, valor: Double) -> Resultado {
    Resultado(lucro: valor - custo, percentual: custo > 0 ? (valor - custo) / custo : 0)
}

// Uma linha do notch ou do painel: ativo manual ou saldo da Binance. Custo e realizado em moedaCusto;
// custo nil é saldo da Binance sem preço médio, que entra no patrimônio mas não no resultado.
struct Linha: Identifiable {
    let ativo: Ativo
    let quantidade: Double
    let custo: Double?
    let cotacao: Cotacao?
    var realizado = 0.0
    var binance = false
    var id: String { (binance ? "binance:" : "") + ativo.id }
    var valor: Double? { cotacao.map { $0.preco * quantidade } }
    var moeda: String { cotacao?.moeda ?? ativo.moedaPrevista }
    // Compras, vendas e preço médio da Binance: cripto em reais (como o formulário pede), mesmo com a cotação em dólar.
    var moedaCusto: String { ativo.cripto ? "BRL" : moeda }

    // Posição cotada ou lucro de vendas: o que somar() conta (e por isso precisa de câmbio).
    var entraNoTotal: Bool { (quantidade > 0 && cotacao != nil) || realizado != 0 }
}

struct Total {
    var moeda: String
    var patrimonio = 0.0
    var hoje = 0.0
    var custo = 0.0
    var valorComCusto = 0.0
    var realizado = 0.0

    var hojePct: Double { patrimonio - hoje > 0 ? hoje / (patrimonio - hoje) : 0 }
    // Em aberto: valor de hoje das posições com custo menos esse custo. O realizado fica à parte.
    var aberto: Resultado { resultado(custo: custo, valor: valorComCusto) }
}

// Quantos reais vale 1 unidade de cada moeda (o real é o pivô), ex.: ["USD": 5.4, "EUR": 6.2].
typealias Cambio = [String: Double]

// Converte passando pelo real. nil se faltar o câmbio de uma das moedas: melhor nada do que um número errado.
// Zero é zero em qualquer moeda: custo e realizado vazios não pedem câmbio.
func converter(_ valor: Double, de origem: String, para destino: String, cambio: Cambio) -> Double? {
    if origem == destino || valor == 0 { return valor }
    let reais = { (moeda: String) in moeda == "BRL" ? 1 : cambio[moeda] }
    guard let a = reais(origem), let b = reais(destino), a > 0, b > 0 else { return nil }
    return valor * a / b
}

// Um total só, na moeda escolhida. Resultado em aberto só conta o que tem custo; o realizado vem das vendas,
// mesmo de posição já zerada. nil quando falta câmbio para alguma linha: um total sem ela estaria errado.
func somar(_ linhas: [Linha], em moeda: String, cambio: Cambio) -> Total? {
    var t = Total(moeda: moeda)
    for linha in linhas where linha.entraNoTotal {
        let emMoeda = { (valor: Double, origem: String) in converter(valor, de: origem, para: moeda, cambio: cambio) }
        guard let realizado = emMoeda(linha.realizado, linha.moedaCusto) else { return nil }
        t.realizado += realizado
        guard linha.quantidade > 0, let c = linha.cotacao else { continue }
        guard let valor = emMoeda(linha.quantidade * c.preco, linha.moeda), let custo = emMoeda(linha.custo ?? 0, linha.moedaCusto)
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

// Uma linha pela mesma conta do total, para o notch, a tabela e o total baterem.
// Sem câmbio, fica na moeda do ativo (e com o símbolo dela): nunca convertida errado. Se nem o custo cabe nela
// (cripto em dólar com compras em reais), sai só o valor.
func resumir(_ linha: Linha, em moeda: String, cambio: Cambio) -> Total {
    let soValor = Linha(ativo: linha.ativo, quantidade: linha.quantidade, custo: nil, cotacao: linha.cotacao)
    return somar([linha], em: moeda, cambio: cambio) ?? somar([linha], em: linha.moeda, cambio: [:])
        ?? somar([soValor], em: linha.moeda, cambio: [:]) ?? Total(moeda: linha.moeda)
}

// Saldos da Binance como linhas, do maior para o menor. Poeira (menos de 1 na moeda da cotação: R$ 1, ou US$ 1 com a
// moeda escolhida em dólar) fica de fora. Sem câmbio a conta é em dólar: o saldo aparece com "sem câmbio" em vez de sumir.
func linhasDeSaldo(_ saldos: [String: Double], precoMedio: [String: Double], snapshot: Snapshot, moeda: String) -> [Linha] {
    let linhas = saldos.map { simbolo, qtd in
        let ativo = Ativo(simbolo: simbolo, cripto: true)
        // Com preço médio (em reais, a moeda de custo da cripto), o saldo entra no resultado em aberto.
        return Linha(ativo: ativo, quantidade: qtd, custo: precoMedio[simbolo].map { $0 * qtd },
                     cotacao: snapshot.cotacao(ativo, moeda: moeda), binance: true)
    }
    let valor = { (l: Linha) in l.valor ?? snapshot.emDolar[l.ativo.id].map { $0.preco * l.quantidade } ?? 0 }
    return linhas.filter { valor($0) >= 1 }.sorted { valor($0) > valor($1) }
}

// Moedas sem câmbio em dia para somar as linhas na moeda escolhida; com alguma, não há total. Cripto sem o dólar
// nem tem preço (somar() a pularia, e o total sairia sem ela): falta o dólar.
func cambiosEmFalta(_ linhas: [Linha], em moeda: String, snapshot: Snapshot) -> [String] {
    var moedas = Set<String>()
    for l in linhas {
        let posicao = l.quantidade > 0 && l.cotacao != nil
        if posicao { moedas.insert(l.moeda) }
        if (posicao && l.custo != nil) || l.realizado != 0 { moedas.insert(l.moedaCusto) }
        if (l.quantidade > 0 || l.realizado != 0) && snapshot.faltaCambio(l) { moedas.insert("USD") }
    }
    return moedas.filter { converter(1, de: $0, para: moeda, cambio: snapshot.cambio) == nil }.sorted()
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
    private(set) var falhas: Set<String> = []  // ativos manuais cuja última busca falhou
    private(set) var erroArquivo: Falha?
    private(set) var saldosBinance: [String: Double] = [:]
    private(set) var precoMedioBinance: [String: Double] = [:]  // em reais, por moeda
    private(set) var erroBinance: (any Error)?
    private var credencial: Credencial? = Chaveiro.ler()
    @ObservationIgnored private var fontes = Fontes()
    @ObservationIgnored private var fila = Fila<Cotacao>()
    @ObservationIgnored private var stream: StreamBinance?
    @ObservationIgnored private var seriesEm = Date.distantPast
    @ObservationIgnored private var seriesPedidas: Set<String> = []
    @ObservationIgnored private var buscandoSeries = false

    // JSON legível, dá pra fazer backup ou editar à mão
    let arquivo = URL.applicationSupportDirectory.appending(path: "StockNotch/carteira.json")

    var binanceConectada: Bool { credencial != nil }
    var atualizadoEm: Date? { snapshot.atualizado }
    // O "agora" das regras de idade: o do snapshot, para a tela inteira usar o mesmo instante.
    var agora: Date { snapshot.em ?? .now }

    var linhas: [Linha] {
        ativos.map { ativo in
            let p = ativo.posicao
            return Linha(ativo: ativo, quantidade: p.quantidade, custo: p.custo, cotacao: cotacao(ativo), realizado: p.realizado)
        }
    }

    var linhasBinance: [Linha] { linhasDeSaldo(saldosBinance, precoMedio: precoMedioBinance, snapshot: snapshot, moeda: moeda) }

    // Preço fica na moeda do ativo; valor, resultado e totais vão para a moeda escolhida nos Ajustes.
    var moeda: String { Ajustes.atual.moeda.rawValue }

    // Do snapshot, com a cripto em dólar se é a moeda escolhida: trocar a moeda troca na hora, sem esperar o ciclo.
    func cotacao(_ ativo: Ativo) -> Cotacao? { snapshot.cotacao(ativo, moeda: moeda) }
    func faltaCambio(_ linha: Linha) -> Bool { snapshot.faltaCambio(linha) }
    // O minigráfico termina na cotação da própria linha: o último ponto é o preço ao lado dele.
    func serie(_ linha: Linha) -> [Ponto]? { linha.cotacao.flatMap { snapshot.serie(linha.ativo, ate: $0) } }

    var total: Total? { semCambio.isEmpty ? somar(linhas + linhasBinance, em: moeda, cambio: snapshot.cambio) : nil }

    // Moedas que não dá para converter agora (sem câmbio ou com câmbio velho); com alguma, não há total.
    var semCambio: [String] { cambiosEmFalta(linhas + linhasBinance, em: moeda, snapshot: snapshot) }

    // Desde quando o câmbio que falta parou de chegar; nil se ele nunca chegou.
    var cambioParado: Date? {
        Set(semCambio + [moeda]).subtracting(["BRL"]).filter { snapshot.cambio[$0] == nil }.compactMap { snapshot.cambioEm[$0] }.min()
    }

    // Ativos cuja cotação parou de chegar há mais de 2 min, com o horário da mais antiga, para o aviso do rodapé.
    var paradas: (simbolos: [String], desde: Date)? {
        let velhas = (linhas + linhasBinance).filter { $0.cotacao?.velha(agora: agora) == true }
        guard let desde = velhas.compactMap(\.cotacao?.recebida).min() else { return nil }
        var vistos = Set<String>()
        return (velhas.map(\.ativo.simbolo).filter { vistos.insert($0).inserted }, desde)
    }

    // Valor, resultado em aberto e realizado de uma linha, na moeda escolhida (ou na do ativo, sem câmbio).
    func resumo(_ linha: Linha) -> Total { resumir(linha, em: moeda, cambio: snapshot.cambio) }

    // Só quem nunca teve cotação: quem já teve mostra a última e, passados 2 min, o aviso de dado velho.
    var simbolosSemCotacao: [String] { ativos.filter { falhas.contains($0.id) && cotacao($0) == nil }.map(\.simbolo) }

    init() {
        stream = StreamBinance { [weak self] moeda, cotacao in self?.receber(moeda, cotacao) }
        guard let data = try? Data(contentsOf: arquivo) else { return }
        do {
            let lido = try Arquivo.ler(data)
            ativos = lido.ativos
            precoMedioBinance = lido.precoMedioBinance
        } catch {
            // Não sobrescreve um arquivo que não conseguiu ler.
            erroArquivo = Falha("Não consegui ler \(arquivo.path). Nada será salvo até corrigir.",
                                "Couldn't read \(arquivo.path). Nothing will be saved until it's fixed.")
        }
    }

    func adicionar(simbolo: String, cripto: Bool, compra: Operacao?) {
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
        fontes.acoes[ativo.id] = nil
        fontes.cripto[ativo.id] = nil
        fontes.series[ativo.id] = nil
        publicar()
        salvar()
    }

    // Confere de novo o que o formulário já validou: venda sem saldo estragaria o preço médio.
    func vender(_ venda: Operacao, de ativo: Ativo) {
        guard let i = ativos.firstIndex(where: { $0.id == ativo.id }),
              ativos[i].problema(venda: true, quantidade: venda.quantidade, data: venda.data) == nil
        else { return }
        ativos[i].vendas.append(venda)
        salvar()
    }

    func remover(_ operacao: Operacao, de ativo: Ativo) {
        guard let i = ativos.firstIndex(where: { $0.id == ativo.id }), ativos[i].podeApagar(operacao) else { return }
        ativos[i].compras.removeAll { $0.id == operacao.id }
        ativos[i].vendas.removeAll { $0.id == operacao.id }
        salvar()
    }

    // O primeiro alerta é que pede a permissão de notificar (depois da resposta o sistema não pergunta de novo).
    // Só entra depois dela: um alerta já atingido dispararia antes de poder notificar e não avisaria nunca.
    func adicionar(_ alerta: Alerta, a ativo: Ativo) async {
        await Notificacoes.pedirPermissao()
        guard let i = ativos.firstIndex(where: { $0.id == ativo.id }) else { return }
        ativos[i].alertas.append(alerta)
        salvar()
        conferirAlertas()
    }

    func remover(_ alerta: Alerta, de ativo: Ativo) {
        guard let i = ativos.firstIndex(where: { $0.id == ativo.id }) else { return }
        ativos[i].alertas.removeAll { $0.id == alerta.id }
        salvar()
    }

    // nil apaga: o saldo volta a contar só no patrimônio.
    func definirPrecoMedio(_ preco: Double?, para moeda: String) {
        precoMedioBinance[moeda] = preco
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
        // Cripto chega pelo stream; BRL e USDT têm preço fixo (o snapshot põe) e não vêm de fonte nenhuma.
        // O stream é só de pares em USDT: moeda que o REST trouxe do par em reais ficaria muda nele.
        let cripto = Set(lista.filter(\.cripto).map(\.simbolo)).subtracting(Fonte.fixas.keys)
        stream?.acompanhar(cripto.filter { fontes.cripto[Ativo(simbolo: $0, cripto: true).id]?.moeda != "BRL" })
        // REST para ações e para a cripto que o stream não trouxe há pouco (conectando, caído, par sem stream).
        // O stream manda cada par a cada 2 s: mais de 5 s sem ele, o REST cobre neste ciclo.
        let inicio = Date.now
        let buscar = lista.filter { a in
            !a.cripto || (cripto.contains(a.simbolo) && fontes.cripto[a.id].map { inicio.timeIntervalSince($0.recebida) > 5 } ?? true)
        }
        async let cambio = Fonte.cambio()
        let resultados = await withTaskGroup(of: (Ativo, Cotacao?).self) { grupo in
            for ativo in buscar { grupo.addTask { (ativo, try? await Fonte.cotacao(ativo)) } }
            var r: [(Ativo, Cotacao?)] = []
            for await item in grupo { r.append(item) }
            return r
        }
        let novoCambio = await cambio
        for case let (ativo, cotacao?) in resultados {
            if !ativo.cripto {
                fontes.acoes[ativo.id] = cotacao
            } else if (fontes.cripto[ativo.id]?.recebida ?? .distantPast) < inicio {
                fontes.cripto[ativo.id] = cotacao  // o stream pode ter trazido um preço mais novo durante a busca
            }
        }
        fontes.cambio.merge(novoCambio) { $1 }
        // Só avisa dos ativos manuais; moeda da Binance sem cotação só some da lista.
        falhas = Set(resultados.filter { $0.1 == nil }.map(\.0.id)).intersection(ativos.map(\.id))
        publicar()
        // À parte: o próximo ciclo de cotações não espera pelas séries.
        Task { await atualizarSeries() }
    }

    // Séries a cada 60 s, só do que aparece na tela (a poeira da Binance não). Ativo novo (adicionado, ou saldo novo
    // na Binance) não espera a volta. Falhou? Fica a anterior, que o ajuste corta quando o dia vira.
    private func atualizarSeries() async {
        var vistos = Set<String>()
        let pedidos = (ativos + linhasBinance.map(\.ativo)).compactMap { a -> (ativo: Ativo, emReais: Bool)? in
            guard vistos.insert(a.id).inserted else { return nil }
            guard a.cripto else { return (a, false) }
            // Cripto no par de onde veio a cotação; sem cotação ainda (ou preço fixo), nada a desenhar.
            return fontes.cripto[a.id].map { (a, $0.moeda == "BRL") }
        }
        let ids = Set(pedidos.map(\.ativo.id))
        guard !buscandoSeries, Date.now.timeIntervalSince(seriesEm) >= 60 || !ids.isSubset(of: seriesPedidas) else { return }
        buscandoSeries = true
        seriesEm = .now
        seriesPedidas = ids
        let comDolar = pedidos.contains { $0.ativo.cripto && !$0.emReais }
        async let dolar = comDolar ? (try? Fonte.serieYahoo("USDBRL=X")) : nil
        let novas = await withTaskGroup(of: (String, Serie?).self) { grupo in
            for p in pedidos { grupo.addTask { (p.ativo.id, try? await Fonte.serie(p.ativo, emReais: p.emReais)) } }
            var r: [(String, Serie?)] = []
            for await item in grupo { r.append(item) }
            return r
        }
        for case let (id, serie?) in novas { fontes.series[id] = serie }
        if let d = await dolar { fontes.serieDolar = d.pontos }
        buscandoSeries = false
        publicar()
    }

    // Tick do stream: espera na fila e sai junto com os outros em meio segundo, no máximo 2 redesenhos por segundo.
    private func receber(_ moeda: String, _ cotacao: Cotacao) {
        guard fila.receber(cotacao, para: Ativo(simbolo: moeda, cripto: true).id) else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            for (id, c) in fila.esvaziar() { fontes.cripto[id] = c }
            // Antes do primeiro ciclo (que traz o câmbio) a cripto sairia "sem câmbio": o tick espera por ele.
            if snapshot.em != nil { publicar() }
        }
    }

    // Republica quando nada publicou há 2 s (ciclo preso na rede, sem stream): o "agora" dos selos e do aviso de
    // dado velho anda com o relógio, não com a rede.
    func envelhecer() {
        guard let em = snapshot.em, Date.now.timeIntervalSince(em) >= 2 else { return }
        publicar()
    }

    // Monta tudo de uma vez a partir das fontes, com um câmbio só: as telas leem só daqui.
    private func publicar() {
        snapshot = Snapshot(fontes, agora: .now)
        conferirAlertas()
    }

    // Cada alerta contra a cotação na moeda dele, a mesma das telas. Só grava quando algum muda de lado:
    // o estado salvo evita avisar de novo ao reabrir o app.
    private func conferirAlertas() {
        var mudou = false
        for i in ativos.indices {
            for j in ativos[i].alertas.indices {
                var alerta = ativos[i].alertas[j]
                guard let c = snapshot.cotacao(para: alerta, de: ativos[i]) else { continue }
                if alerta.conferir(c) { alerta.notificar(ativos[i].simbolo, c) }
                if alerta != ativos[i].alertas[j] {
                    ativos[i].alertas[j] = alerta
                    mudou = true
                }
            }
        }
        if mudou { salvar() }
    }

    private func salvar() {
        guard erroArquivo == nil else { return }
        do {
            try FileManager.default.createDirectory(at: arquivo.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Arquivo(ativos: ativos, precoMedioBinance: precoMedioBinance).dados().write(to: arquivo, options: .atomic)
        } catch {
            // Só o código do erro: o texto do sistema viria no idioma em que o app abriu.
            let codigo = (error as NSError).code
            erroArquivo = Falha("Não consegui salvar \(arquivo.path) (erro \(codigo)).", "Couldn't save \(arquivo.path) (error \(codigo)).")
        }
    }
}

// Conteúdo do carteira.json. Antes das vendas era só a lista de ativos; ler() aceita os dois formatos.
// Grava sempre o objeto: uma versão antiga do app recusa o arquivo (e não salva por cima) em vez de perder as vendas.
struct Arquivo: Codable, Equatable {
    var ativos: [Ativo] = []
    var precoMedioBinance: [String: Double] = [:]

    static func ler(_ dados: Data) throws -> Arquivo {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let antigo = try? decoder.decode([Ativo].self, from: dados) { return Arquivo(ativos: antigo) }
        return try decoder.decode(Arquivo.self, from: dados)
    }

    func dados() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

extension Arquivo {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ativos = try c.decodeIfPresent([Ativo].self, forKey: .ativos) ?? []
        precoMedioBinance = try c.decodeIfPresent([String: Double].self, forKey: .precoMedioBinance) ?? [:]
    }
}

// Texto nos dois idiomas; mensagem(_:) escolhe na hora de mostrar.
struct Falha: Error {
    let pt: String
    let en: String
    var codigo: Int?  // o código da Binance, quando ele decide o que fazer (ex.: -1121, símbolo inválido)
    init(_ pt: String, _ en: String, codigo: Int? = nil) {
        self.pt = pt
        self.en = en
        self.codigo = codigo
    }
}

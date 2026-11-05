import CryptoKit
import Foundation
import Security

struct Credencial: Sendable {
    let chave: String
    let segredo: String
}

// Conta da Binance, só leitura. Endpoints: https://developers.binance.com/docs/binance-spot-api-docs
enum Binance {
    // Recusa chave que pode negociar, transferir ou sacar: o app só precisa ler saldos.
    static func verificar(_ cred: Credencial) async throws {
        let p: Permissoes = try await assinado("/sapi/v1/account/apiRestrictions", "", cred)
        guard p.soLeitura else {
            throw Falha("Use uma chave só de leitura: na Binance, deixe marcado apenas “Ativar leitura”.",
                        "Use a read-only key: on Binance, leave only “Enable Reading” checked.")
        }
    }

    static func saldos(_ cred: Credencial) async throws -> [String: Double] {
        struct Conta: Decodable {
            let balances: [Saldo]
            struct Saldo: Decodable { let asset, free, locked: String }
        }
        let conta: Conta = try await assinado("/api/v3/account", "omitZeroBalances=true", cred)
        var saldos: [String: Double] = [:]
        for s in conta.balances {
            let qtd = (Double(s.free) ?? 0) + (Double(s.locked) ?? 0)
            // Simple Earn flexível aparece como "LD" + moeda (LDBTC); LDO (Lido) tem 3 letras e escapa
            let moeda = s.asset.hasPrefix("LD") && s.asset.count > 3 ? String(s.asset.dropFirst(2)) : s.asset
            if qtd > 0 { saldos[moeda, default: 0] += qtd }
        }
        return saldos
    }

    static func assinatura(_ consulta: String, segredo: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(consulta.utf8), using: SymmetricKey(data: Data(segredo.utf8)))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private struct Hora: Decodable { let serverTime: Int64 }

    fileprivate static func assinado<T: Decodable>(_ caminho: String, _ parametros: String, _ cred: Credencial) async throws -> T {
        // Usa o relógio da Binance: com o do Mac adiantado ou atrasado ela recusa o pedido (erro -1021).
        let hora: Hora = try await baixar("https://api.binance.com/api/v3/time")
        let consulta = (parametros.isEmpty ? "" : parametros + "&") + "recvWindow=10000&timestamp=\(hora.serverTime)"
        let assinatura = assinatura(consulta, segredo: cred.segredo)
        guard let url = URL(string: "https://api.binance.com\(caminho)?\(consulta)&signature=\(assinatura)") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue(cred.chave, forHTTPHeaderField: "X-MBX-APIKEY")
        return try await baixar(req)
    }
}

// Resposta do apiRestrictions: só os campos ligados (true). Lista de permitidos, não de proibidos: uma permissão
// nova da Binance (como as opções europeias ou a Portfolio Margin) é recusada até alguém conferir que só lê.
struct Permissoes: Decodable {
    let ligadas: Set<String>

    static let deLeitura: Set<String> = ["enableReading", "enableFixReadOnly"]

    var soLeitura: Bool {
        ligadas.contains("enableReading")
            && ligadas.allSatisfy { !($0.hasPrefix("enable") || $0.hasPrefix("permits")) || Self.deLeitura.contains($0) }
    }

    init(from decoder: any Decoder) throws {
        // Campo que não é true (false, número, texto, null) não liga nada.
        struct Campo: Decodable {
            let ligado: Bool
            init(from decoder: any Decoder) throws { ligado = (try? decoder.singleValueContainer().decode(Bool.self)) ?? false }
        }
        ligadas = Set(try decoder.singleValueContainer().decode([String: Campo].self).filter(\.value.ligado).keys)
    }
}

// A Secret Key fica nas Chaves do macOS (Keychain), nunca no carteira.json.
enum Chaveiro {
    private static let servico = "io.github.rodrigovixc.stocknotch.binance"

    static func salvar(_ cred: Credencial) throws {
        apagar()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servico,
            kSecAttrAccount as String: cred.chave,
            kSecValueData as String: Data(cred.segredo.utf8),
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Falha("Não consegui guardar a chave no Keychain (erro \(status)).", "Couldn't save the key to the Keychain (error \(status)).")
        }
    }

    // nil só quando não há chave salva. Chave salva que o macOS não deixou ler (janela de permissão cancelada ou
    // fechada, Keychain ainda trancado logo no login) é erro: dizer "não conectada" faria parecer que a chave sumiu.
    static func ler() throws -> Credencial? {
        let busca: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servico,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultado: CFTypeRef?
        let status = SecItemCopyMatching(busca as CFDictionary, &resultado)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let item = resultado as? [String: Any],
              let chave = item[kSecAttrAccount as String] as? String,
              let dados = item[kSecValueData as String] as? Data,
              let segredo = String(data: dados, encoding: .utf8)
        else {
            throw Falha("A chave da Binance continua salva, mas o macOS não deixou o app lê-la (erro \(status)). Clique em Tentar de novo e, na janela do macOS, em Sempre permitir.",
                        "Your Binance key is still saved, but macOS didn't let the app read it (error \(status)). Click Try Again and, in the macOS window, Always Allow.",
                        codigo: Int(status))
        }
        return Credencial(chave: chave, segredo: segredo)
    }

    static func apagar() {
        let busca: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servico]
        SecItemDelete(busca as CFDictionary)
    }
}

// Uma troca na conta: deu `qtdDe` de `de` e recebeu `qtdPara` de `para` (ordem no Spot ou Converter).
struct Troca: Codable, Hashable, Sendable {
    let id: String
    let em: Date
    let de: String, qtdDe: Double
    let para: String, qtdPara: Double

    static let dolares: Set<String> = ["USDT", "USDC", "FDUSD", "BUSD", "TUSD"]

    // Quanto valeu em reais: pelo lado em reais, se houver; senão pelo lado em dólar; senão pelo que foi dado.
    func emReais(_ preco: (String, Date) -> Double?) -> Double? {
        if de == "BRL" { return qtdDe }
        if para == "BRL" { return qtdPara }
        if !Self.dolares.contains(de), Self.dolares.contains(para) { return preco(para, em).map { $0 * qtdPara } }
        return preco(de, em).map { $0 * qtdDe }
    }
}

// Preço médio em reais de cada moeda pelas trocas, na mesma regra das operações manuais (Posicao): receber é compra,
// dar é venda. Venda de moeda que chegou de fora (depósito, Earn) tira só o que as trocas mostram.
func precoMedioEmReais(_ trocas: [Troca], moedas: Set<String>, preco: (String, Date) -> Double?) -> [String: Double] {
    var posicoes: [String: Posicao] = [:]
    for t in trocas.sorted(by: { $0.em < $1.em }) where t.qtdDe > 0 && t.qtdPara > 0 {
        guard moedas.contains(t.de) || moedas.contains(t.para), let valor = t.emReais(preco) else { continue }
        for (moeda, qtd, venda) in [(t.para, t.qtdPara, false), (t.de, t.qtdDe, true)] where moedas.contains(moeda) {
            posicoes[moeda, default: Posicao()]
                .aplicar(Lancamento(operacao: Operacao(quantidade: qtd, preco: valor / qtd, data: t.em), venda: venda))
        }
    }
    return posicoes.compactMapValues { $0.quantidade > 0 ? $0.precoMedio : nil }
}

// O que já veio da conta, guardado em binance-trocas.json para a próxima busca pegar só o que é novo.
struct HistoricoBinance: Codable, Sendable {
    var trocas: [String: Troca] = [:]
    var ultimoId: [String: Int64] = [:]  // por par do Spot
    // ponytail: o Converter não diz desde quando há histórico; 2020 cobre a conta de quase todo mundo.
    var converterAte = Date(timeIntervalSince1970: 1_577_836_800)  // 2020-01-01
    var precoMedio: [String: Double] = [:]
}

extension Binance {
    static let cotacoesDoSpot = ["BRL", "USDT", "USDC", "FDUSD"]

    // Ordens executadas no Spot (dos pares das moedas em `moedas`) e trocas do Converter, a partir de onde parou.
    // Para no primeiro erro: o que já chegou fica em `h`.
    static func buscarTrocas(_ h: inout HistoricoBinance, moedas: Set<String>, _ cred: Credencial) async throws {
        struct Ordem: Decodable {
            let id: Int64
            let qty, quoteQty, commission, commissionAsset: String
            let time: Int64
            let isBuyer: Bool
        }
        for base in moedas.sorted() {
            for cotacao in cotacoesDoSpot where cotacao != base {
                let par = base + cotacao
                while true {
                    let desde = (h.ultimoId[par] ?? -1) + 1
                    let ordens: [Ordem]
                    do {
                        ordens = try await assinado("/api/v3/myTrades", "symbol=\(par)&fromId=\(desde)&limit=1000", cred)
                    } catch let erro as Falha where erro.codigo == -1121 { break }  // par que não existe
                    for o in ordens {
                        guard var qtd = Double(o.qty), var total = Double(o.quoteQty), let taxa = Double(o.commission) else { continue }
                        // Taxa paga na moeda recebida diminui o que chegou; em BNB fica de fora.
                        if o.isBuyer, o.commissionAsset == base { qtd -= taxa }
                        if !o.isBuyer, o.commissionAsset == cotacao { total -= taxa }
                        let em = Date(timeIntervalSince1970: Double(o.time) / 1000)
                        h.trocas["s:\(par):\(o.id)"] = o.isBuyer
                            ? Troca(id: "s:\(par):\(o.id)", em: em, de: cotacao, qtdDe: total, para: base, qtdPara: qtd)
                            : Troca(id: "s:\(par):\(o.id)", em: em, de: base, qtdDe: qtd, para: cotacao, qtdPara: total)
                        h.ultimoId[par] = max(h.ultimoId[par] ?? -1, o.id)
                    }
                    if ordens.count < 1000 { break }
                }
            }
        }

        struct Fluxo: Decodable {
            let list: [Item]
            let moreData: Bool?
            struct Item: Decodable {
                let orderId: Int64
                let orderStatus, fromAsset, fromAmount, toAsset, toAmount: String
                let createTime: Int64
            }
        }
        // Janelas de 30 dias (o máximo do Converter). Cada pedido pesa 3000 de 180000 por minuto: um por segundo.
        let mes: Int64 = 30 * 86_400_000
        let agora = Int64(Date.now.timeIntervalSince1970 * 1000)
        var inicio = Int64(h.converterAte.timeIntervalSince1970 * 1000)
        while inicio < agora {
            let fim = min(inicio + mes - 1, agora)
            let f: Fluxo = try await assinado("/sapi/v1/convert/tradeFlow", "startTime=\(inicio)&endTime=\(fim)&limit=1000", cred)
            for i in f.list where i.orderStatus == "SUCCESS" {
                guard let de = Double(i.fromAmount), let para = Double(i.toAmount) else { continue }
                h.trocas["c:\(i.orderId)"] = Troca(id: "c:\(i.orderId)", em: Date(timeIntervalSince1970: Double(i.createTime) / 1000),
                                                   de: i.fromAsset, qtdDe: de, para: i.toAsset, qtdPara: para)
            }
            // Janela com mais de 1000: continua dela, depois da última que veio.
            if f.moreData == true, let ultima = f.list.map(\.createTime).max() { inicio = ultima + 1 } else { inicio = fim + 1 }
            h.converterAte = Date(timeIntervalSince1970: Double(inicio) / 1000)
            try await Task.sleep(for: .seconds(1))
        }
    }

    // Preço em reais, dia a dia desde `desde`, das moedas que avaliam as trocas: dólar pelo USDTBRL, as outras pelo
    // par em USDT vezes o dólar. A que não tem par fica de fora (e a troca dela também).
    static func precosEmReais(_ moedas: Set<String>, desde: Date) async throws -> [String: [Ponto]] {
        func diarios(_ par: String) async throws -> [Ponto] {
            var pontos: [Ponto] = []
            var inicio = Int64(desde.timeIntervalSince1970 * 1000)
            while true {
                let velas: [VelaBinance] = try await baixar("https://api.binance.com/api/v3/klines?symbol=\(par)&interval=1d&startTime=\(inicio)&limit=1000")
                pontos += velas.map { Ponto(em: $0.fim, preco: $0.fechamento) }
                guard velas.count == 1000, let ultima = velas.last else { return pontos }
                inicio = Int64(ultima.fim.timeIntervalSince1970 * 1000) + 1
            }
        }
        let dolar = try await diarios("USDTBRL")
        var precos = ["USDT": dolar]
        for m in moedas.subtracting(Troca.dolares).subtracting(["BRL"]) {
            guard let emDolar = try? await diarios(m + "USDT") else { continue }
            precos[m] = emDolar.compactMap { p in valor(dolar, em: p.em).map { Ponto(em: p.em, preco: p.preco * $0) } }
        }
        return precos
    }
}

import Foundation
import SwiftUI

// Últimas notícias dos ativos da carteira, pelo RSS de busca do Google Notícias (sem chave, em português, com a
// imprensa de investimentos do Brasil). O Yahoo só tem notícia de ação americana, em inglês.
struct Noticia: Identifiable, Hashable, Sendable {
    let titulo: String
    let fonte: String
    let link: URL
    let em: Date
    let simbolo: String
    var id: String { link.absoluteString }
}

enum Noticias {
    // Cripto pelo nome: "SOL" ou "BNB" puros trazem página de conversão de corretora. Moeda fora da lista vai pelo símbolo.
    static let nomes = [
        "BTC": "Bitcoin", "ETH": "Ethereum", "SOL": "Solana", "XRP": "XRP", "BNB": "BNB", "ADA": "Cardano",
        "DOGE": "Dogecoin", "TRX": "Tron", "ATOM": "Cosmos", "GLM": "Golem", "DOT": "Polkadot", "LINK": "Chainlink",
        "AVAX": "Avalanche", "POL": "Polygon", "LTC": "Litecoin", "USDT": "Tether", "USDC": "USDC", "SHIB": "Shiba Inu",
        "TON": "Toncoin", "SUI": "Sui", "PEPE": "Pepe",
    ]

    // O termo que a notícia precisa ter no título: o ticker (a imprensa escreve "Banco do Brasil (BBAS3)") ou o nome
    // da cripto. A busca do Google é solta; sem esse filtro, SNAG11 traria notícia de outros fundos.
    static func termo(_ ativo: Ativo) -> String { ativo.cripto ? nomes[ativo.simbolo] ?? ativo.simbolo : ativo.simbolo }

    static func buscar(_ ativo: Ativo, ingles: Bool) async throws -> [Noticia] {
        let termo = termo(ativo)
        // B3 sempre em português: é onde a imprensa escreve sobre ela. O resto no idioma do app.
        let ingles = ingles && ativo.classe != .b3
        var c = URLComponents(string: "https://news.google.com/rss/search")!
        c.queryItems = [URLQueryItem(name: "q", value: "\"\(termo)\"\(ativo.cripto ? (ingles ? " crypto" : " cripto") : "") when:2d")]
            + (ingles ? [.init(name: "hl", value: "en-US"), .init(name: "gl", value: "US"), .init(name: "ceid", value: "US:en")]
                      : [.init(name: "hl", value: "pt-BR"), .init(name: "gl", value: "BR"), .init(name: "ceid", value: "BR:pt-419")])
        guard let url = c.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (dados, resposta) = try await URLSession.shared.data(for: req)
        guard (resposta as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return lerRSS(dados, simbolo: ativo.simbolo).filter { $0.titulo.localizedCaseInsensitiveContains(termo) }
    }

    // Itens do RSS: título (o Google põe " - Fonte" no fim), fonte, link e data (RFC 822).
    static func lerRSS(_ dados: Data, simbolo: String) -> [Noticia] {
        final class Leitor: NSObject, XMLParserDelegate {
            var itens: [[String: String]] = []
            var atual: [String: String]?
            var texto = ""
            func parser(_ p: XMLParser, didStartElement nome: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
                if nome == "item" { atual = [:] }
                texto = ""
            }
            func parser(_ p: XMLParser, foundCharacters s: String) { texto += s }
            func parser(_ p: XMLParser, didEndElement nome: String, namespaceURI: String?, qualifiedName: String?) {
                if nome == "item", let a = atual { itens.append(a); atual = nil } else { atual?[nome] = texto.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        let leitor = Leitor()
        let parser = XMLParser(data: dados)
        parser.delegate = leitor
        parser.parse()
        let datas = DateFormatter()
        datas.locale = Locale(identifier: "en_US_POSIX")
        datas.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return leitor.itens.compactMap { i in
            guard let titulo = i["title"], let link = i["link"].flatMap(URL.init(string:)),
                  let em = i["pubDate"].flatMap(datas.date(from:)) else { return nil }
            let fonte = i["source"] ?? ""
            let limpo = !fonte.isEmpty && titulo.hasSuffix(" - " + fonte) ? String(titulo.dropLast(fonte.count + 3)) : titulo
            return Noticia(titulo: limpo, fonte: fonte, link: link, em: em, simbolo: simbolo)
        }
    }
}

extension Carteira {
    // Os ativos que pedem notícia: comprados, saldos da Binance e a lista de desejos, sem repetir o símbolo.
    var ativosComNoticia: [Ativo] {
        var vistos = Set<String>()
        return (linhas.map(\.ativo) + linhasBinance.map(\.ativo)).filter { !Fonte.fixas.keys.contains($0.simbolo) && vistos.insert($0.simbolo).inserted }
    }
}

// As notícias mais novas dos ativos, da mais recente para a mais antiga. Busca ao aparecer e de 10 em 10 minutos
// enquanto está na tela (o Google atualiza em minutos; mais que isso seria pedir o mesmo de novo).
struct ColunaNoticias: View {
    @Environment(Carteira.self) private var carteira
    var limite = 8
    var escuro = true  // no notch o texto é branco; no painel segue o tema

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "newspaper")
                Text(tr("ÚLTIMAS NOTÍCIAS", "LATEST NEWS")).tracking(0.6)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            if carteira.noticias.isEmpty {
                Text(carteira.noticiasEm == nil ? tr("Buscando…", "Loading…") : tr("Nada nos últimos 2 dias.", "Nothing in the last 2 days."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ForEach(carteira.noticias.prefix(limite)) { n in
                Link(destination: n.link) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(n.titulo)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 5) {
                            Text(n.simbolo).fontWeight(.semibold).foregroundStyle(Color.accentColor)
                            Text("·")
                            Text(n.fonte).lineLimit(1)
                            Text("·")
                            Text(momento(n.em, agora: carteira.agora))
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(escuro ? Color.white : Color.primary)
                .help(tr("Abrir no navegador", "Open in browser"))
            }
        }
        .task(id: carteira.ativosComNoticia.map(\.id)) {
            while !Task.isCancelled {
                await carteira.carregarNoticias()
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }
}

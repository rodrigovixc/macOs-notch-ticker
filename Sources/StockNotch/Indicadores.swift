import Foundation

// Indicadores de uma ação para o detalhe do notch (ao parar o mouse na linha): o pregão do dia e os fundamentos.
// Vêm da cotação completa do Yahoo, que pede um "crumb" (ver buscarCrumb). Campo ausente fica "—".
struct Indicadores: Decodable, Equatable {
    let currency: String?
    let regularMarketOpen: Double?
    let regularMarketDayHigh: Double?
    let regularMarketDayLow: Double?
    let regularMarketPreviousClose: Double?
    let regularMarketVolume: Double?
    let averageDailyVolume3Month: Double?
    let fiftyTwoWeekHigh: Double?
    let fiftyTwoWeekLow: Double?
    let marketCap: Double?
    let trailingPE: Double?
    let epsTrailingTwelveMonths: Double?
    let dividendYield: Double?  // em pontos percentuais (7.23 = 7,23%)
    let priceToBook: Double?
}

private struct RespostaIndicadores: Decodable {
    struct Lista: Decodable { let result: [Indicadores] }
    let quoteResponse: Lista
}

// O crumb vale junto com o cookie que fc.yahoo.com entrega (o URLSession guarda o cookie sozinho).
func buscarCrumb() async throws -> String {
    var pedido = URLRequest(url: URL(string: "https://fc.yahoo.com")!)
    pedido.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    _ = try? await URLSession.shared.data(for: pedido)  // responde 404, mas com o cookie: é o que importa
    pedido.url = URL(string: "https://query1.finance.yahoo.com/v1/test/getcrumb")
    let (dados, resposta) = try await URLSession.shared.data(for: pedido)
    let crumb = String(decoding: dados, as: UTF8.self)
    guard (resposta as? HTTPURLResponse)?.statusCode == 200, !crumb.isEmpty, !crumb.contains("<") else {
        throw Falha("O Yahoo não liberou os indicadores agora.", "Yahoo didn't allow the indicators right now.")
    }
    return crumb
}

func buscarIndicadores(_ simbolo: String, crumb: String) async throws -> Indicadores {
    let s = simbolo.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? simbolo
    let c = crumb.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? crumb
    let r: RespostaIndicadores = try await baixar("https://query1.finance.yahoo.com/v7/finance/quote?symbols=\(s)&crumb=\(c)")
    guard let i = r.quoteResponse.result.first else { throw URLError(.badServerResponse) }
    return i
}

// Busca de ativos pelo nome ou código, para o formulário de adicionar ("petro" acha PETR4, "bitcoin" acha BTC).
struct Sugestao: Identifiable, Hashable {
    let simbolo: String  // como o app guarda: PETR4 (sem .SA), BTC (sem -USD)
    let nome: String
    let cripto: Bool
    let bolsa: String
    var id: String { (cripto ? "c:" : "a:") + simbolo }
}

struct RespostaBusca: Decodable {
    struct Item: Decodable {
        let symbol: String
        let shortname: String?
        let longname: String?
        let quoteType: String?
        let exchDisp: String?
    }
    let quotes: [Item]?

    // Só o que o app acompanha: ações, ETFs e cripto cotada em dólar (vira a moeda da Binance). Fundos, futuros e
    // índices ficam de fora; o mesmo ativo em duas listagens aparece uma vez.
    var sugestoes: [Sugestao] {
        var vistas = Set<String>()
        return (quotes ?? []).compactMap { q -> Sugestao? in
            let cripto = q.quoteType == "CRYPTOCURRENCY"
            guard cripto ? q.symbol.hasSuffix("-USD") : ["EQUITY", "ETF"].contains(q.quoteType ?? "") else { return nil }
            let simbolo = cripto ? String(q.symbol.dropLast(4)) : q.symbol.hasSuffix(".SA") ? String(q.symbol.dropLast(3)) : q.symbol
            let nome = (q.longname ?? q.shortname ?? simbolo).split(separator: " ").joined(separator: " ")
            let s = Sugestao(simbolo: simbolo, nome: nome, cripto: cripto, bolsa: cripto ? "Cripto" : q.exchDisp ?? "")
            return vistas.insert(s.id).inserted ? s : nil
        }
    }
}

func buscarAtivos(_ texto: String) async throws -> [Sugestao] {
    let q = texto.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? texto
    let r: RespostaBusca = try await baixar("https://query1.finance.yahoo.com/v1/finance/search?q=\(q)&quotesCount=10&newsCount=0&listsCount=0")
    return r.sugestoes
}

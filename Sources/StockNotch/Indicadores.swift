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

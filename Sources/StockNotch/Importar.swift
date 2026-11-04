import Foundation

// Importação de operações por CSV, uma por linha: tipo, ativo, cripto, quantidade, preço, data.
//   compra,PETR4,nao,200,38.40,2026-03-10
// Ponto decimal sem milhar e data ano-mês-dia, nos dois idiomas: "1.500" nunca é ambíguo. Vírgula ou ponto e
// vírgula separam as colunas; linha vazia, comentário (#) e o cabeçalho ficam de fora.

// Uma operação lida do arquivo, ainda fora da carteira.
struct Importada {
    let ativo: Ativo  // só símbolo e tipo; as operações dele estão na carteira
    let venda: Bool
    let operacao: Operacao
}

// Uma linha do arquivo, com o número dela para o aviso de erro.
struct LinhaCSV: Identifiable {
    let numero: Int
    let resultado: Result<Importada, Falha>
    var id: Int { numero }
}

extension Importada {
    // Aplica na carteira (uma cópia, na leitura) com as regras do formulário. A ordem do arquivo conta:
    // a venda pode vir depois da compra que dá o saldo.
    func aplicar(em ativos: inout [Ativo], agora: Date = .now, calendario: Calendar = .current) -> Problema? {
        let i = ativos.firstIndex { $0.id == ativo.id } ?? {
            ativos.append(ativo)
            return ativos.count - 1
        }()
        if let problema = ativos[i].problema(venda: venda, quantidade: operacao.quantidade, data: operacao.data,
                                             agora: agora, calendario: calendario) {
            return problema
        }
        if venda { ativos[i].vendas.append(operacao) } else { ativos[i].compras.append(operacao) }
        return nil
    }
}

func lerCSV(_ texto: String, ativos: [Ativo], agora: Date = .now, calendario: Calendar = .current) -> [LinhaCSV] {
    var carteira = ativos
    var linhas: [LinhaCSV] = []
    var cabecalho = true
    for (i, bruta) in texto.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
        let linha = bruta.trimmingCharacters(in: .whitespaces)
        if linha.isEmpty || linha.hasPrefix("#") { continue }
        let campos = linha.split(omittingEmptySubsequences: false) { $0 == "," || $0 == ";" }
            .map { $0.trimmingCharacters(in: .whitespaces.union(["\""])).lowercased().folding(options: .diacriticInsensitive, locale: nil) }
        defer { cabecalho = false }
        if cabecalho && ["tipo", "type"].contains(campos[0]) { continue }
        let resultado = ler(campos, calendario: calendario).flatMap { importada -> Result<Importada, Falha> in
            switch importada.aplicar(em: &carteira, agora: agora, calendario: calendario) {
            case nil: .success(importada)
            case .dataFutura: .failure(Falha("Data no futuro.", "Date is in the future."))
            case .semSaldo(let disponivel):
                .failure(Falha("Venda maior que o saldo nessa data (\(disponivel.formatted())).",
                               "Sale is larger than the holding on that date (\(disponivel.formatted()))."))
            }
        }
        linhas.append(LinhaCSV(numero: i + 1, resultado: resultado))
    }
    return linhas
}

private func ler(_ c: [String], calendario: Calendar) -> Result<Importada, Falha> {
    guard c.count == 6 else {
        // Coluna a mais costuma ser vírgula decimal ("38,40"), que também separa colunas.
        return .failure(Falha("Esperava 6 colunas (tipo, ativo, cripto, quantidade, preço, data), veio \(c.count). Use ponto nos decimais (38.40).",
                              "Expected 6 columns (type, symbol, crypto, quantity, price, date), got \(c.count). Use a decimal point (38.40)."))
    }
    let venda: Bool
    switch c[0] {
    case "compra", "buy": venda = false
    case "venda", "sell": venda = true
    default: return .failure(Falha("Tipo \"\(c[0])\": use compra ou venda.", "Type \"\(c[0])\": use buy or sell."))
    }
    let cripto: Bool
    switch c[2] {
    case "sim", "s", "yes", "y", "true", "1": cripto = true
    case "nao", "n", "no", "false", "0": cripto = false
    default: return .failure(Falha("Cripto \"\(c[2])\": use sim ou nao.", "Crypto \"\(c[2])\": use yes or no."))
    }
    let simbolo = Ativo.normalizar(c[1], cripto: cripto)
    guard !simbolo.isEmpty else { return .failure(Falha("Falta o ativo.", "Missing symbol.")) }
    // Só dígitos e ponto: Double() aceitaria "1e5", "inf" e "0x10".
    func numero(_ s: String) -> Double? {
        s.wholeMatch(of: #/\d+(\.\d+)?/#) != nil ? Double(s).flatMap { $0 > 0 && $0.isFinite ? $0 : nil } : nil
    }
    guard let quantidade = numero(c[3]), let preco = numero(c[4]) else {
        return .failure(Falha("Quantidade e preço maiores que zero, com ponto decimal e sem milhar (1500 ou 38.40).",
                              "Quantity and price above zero, with a decimal point and no thousands separator (1500 or 38.40)."))
    }
    // Meio-dia: o dia não muda com o fuso. Data que não existe (30/02) o calendário empurraria para março.
    guard let m = c[5].wholeMatch(of: #/(\d{4})-(\d{2})-(\d{2})/#),
          let data = calendario.date(from: DateComponents(year: Int(m.1), month: Int(m.2), day: Int(m.3), hour: 12)),
          calendario.component(.day, from: data) == Int(m.3)
    else {
        return .failure(Falha("Data \"\(c[5])\": use ano-mês-dia (2026-03-10).", "Date \"\(c[5])\": use year-month-day (2026-03-10)."))
    }
    return .success(Importada(ativo: Ativo(simbolo: simbolo, cripto: cripto), venda: venda,
                              operacao: Operacao(quantidade: quantidade, preco: preco, data: data)))
}

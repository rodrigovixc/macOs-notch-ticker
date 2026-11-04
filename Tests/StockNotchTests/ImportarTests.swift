import Foundation
import Testing
@testable import StockNotch

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private let agora = utc.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 15))!

private func ler(_ texto: String, ativos: [Ativo] = []) -> [LinhaCSV] { lerCSV(texto, ativos: ativos, agora: agora, calendario: utc) }

@Test func importaCSVValido() throws {
    // Cabeçalho, CRLF, comentário, linha vazia, ponto e vírgula, aspas, acento e maiúsculas: tudo vale.
    let texto = "tipo,ativo,cripto,quantidade,preco,data\r\n# carteira da corretora\r\n\r\n"
        + "compra,petr4,nao,200,38.40,2026-03-10\r\n"
        + "Venda;\"PETR4\";Não;50;47.10;2026-09-02\r\n"
        + "buy,BTCBRL,yes,0.015,385000,2026-06-01"
    let linhas = ler(texto)
    #expect(linhas.map(\.numero) == [4, 5, 6])
    let ops = try linhas.map { try $0.resultado.get() }
    #expect(ops.map(\.ativo.id) == ["a:PETR4", "a:PETR4", "c:BTC"])
    #expect(ops.map(\.venda) == [false, true, false])
    #expect(ops[1].operacao.quantidade == 50 && ops[1].operacao.preco == 47.10)
    #expect(utc.dateComponents([.year, .month, .day], from: ops[2].operacao.data) == DateComponents(year: 2026, month: 6, day: 1))
}

@Test func importaCSVComErros() {
    let jaTem = [Ativo(simbolo: "VALE3", cripto: false, compras: [Operacao(quantidade: 10, preco: 60, data: agora)])]
    let texto = """
        compra,PETR4,nao,200,"38,40",2026-03-10
        compra;PETR4;nao;1e5;38.40;2026-03-10
        compra,PETR4,nao,1.500.000,38.40,2026-03-10
        compra,PETR4,nao,0,38.40,2026-03-10
        compra,PETR4,nao,200,38.40,2026-11-05
        compra,PETR4,nao,200,38.40,2026-02-30
        compra,PETR4,nao,200,38.40,10/03/2026
        troca,PETR4,nao,200,38.40,2026-03-10
        compra,PETR4,talvez,200,38.40,2026-03-10
        compra,,nao,200,38.40,2026-03-10
        compra,PETR4,nao,200,38.40
        venda,PETR4,nao,10,40,2026-03-10
        venda,VALE3,nao,11,61,2026-11-04
        venda,VALE3,nao,10,61,2026-11-04
        """
    let linhas = ler(texto, ativos: jaTem)
    #expect(linhas.count == 14)
    // Só a última passa: a venda de 10 VALE3 que a carteira já tem.
    #expect(linhas.map { (try? $0.resultado.get()) != nil } == Array(repeating: false, count: 13) + [true])
    // "38,40" entre aspas tem a vírgula decimal: com vírgula separando as colunas, viraria 7 colunas.
    #expect(linhas[0].resultado.mensagemPT.contains("7"))
    #expect(linhas[4].resultado.mensagemPT == "Data no futuro.")
    #expect(linhas[12].resultado.mensagemPT.contains("saldo"))
}

private extension Result where Failure == Falha {
    var mensagemPT: String { if case .failure(let f) = self { f.pt } else { "" } }
}

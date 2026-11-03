import Foundation

// Compra ou venda: os mesmos campos, cada uma na sua lista do ativo (compras, vendas) no carteira.json.
struct Operacao: Codable, Identifiable, Hashable {
    var id = UUID()
    var quantidade: Double
    var preco: Double
    var data: Date
}

// Uma operação com o seu tipo, para as contas e para a lista de operações.
struct Lancamento: Identifiable {
    let operacao: Operacao
    let venda: Bool
    var id: UUID { operacao.id }
}

// Posição pelo método do preço médio, na moeda do ativo.
struct Posicao: Equatable {
    var quantidade = 0.0
    var custo = 0.0
    var realizado = 0.0
    var semSaldo = false  // alguma venda passou do que havia na data (só acontece com o JSON editado à mão)

    var precoMedio: Double { quantidade > 0 ? custo / quantidade : 0 }

    // Folga para o arredondamento do Double: vender tudo de 0,1 + 0,2 tem que zerar a posição.
    static func folga(_ quantidade: Double) -> Double { 1e-9 + quantidade.magnitude * 1e-12 }

    // A compra soma quantidade e custo. A venda tira pelo preço médio, que não muda,
    // e a diferença para o preço de venda vira lucro realizado.
    mutating func aplicar(_ l: Lancamento) {
        let op = l.operacao
        guard l.venda else {
            quantidade += op.quantidade
            custo += op.quantidade * op.preco
            return
        }
        if op.quantidade > quantidade + Self.folga(quantidade) { semSaldo = true }
        let vendida = min(op.quantidade, quantidade)
        let medio = precoMedio
        realizado += (op.preco - medio) * vendida
        quantidade -= vendida
        custo -= medio * vendida
        // Zerou: a próxima compra começa um preço médio novo.
        if quantidade <= Self.folga(quantidade) {
            quantidade = 0
            custo = 0
        }
    }
}

extension Posicao {
    // Fora do corpo da struct para manter o init membro a membro (e o Posicao() vazio).
    init(_ lancamentos: [Lancamento]) {
        self.init()
        for l in lancamentos { aplicar(l) }
    }
}

// O que impede registrar uma operação, para o formulário avisar perto do campo.
enum Problema: Equatable {
    case dataFutura
    case semSaldo(disponivel: Double)
}

extension Ativo {
    // Na ordem em que contam: por dia e, no mesmo dia, compras antes das vendas
    // (o formulário só pede o dia, então a hora gravada não diz o que veio antes).
    func lancamentos(calendario: Calendar = .current) -> [Lancamento] {
        let todos = compras.map { Lancamento(operacao: $0, venda: false) } + vendas.map { Lancamento(operacao: $0, venda: true) }
        return todos.sorted { a, b in
            let dia = (calendario.startOfDay(for: a.operacao.data), calendario.startOfDay(for: b.operacao.data))
            if dia.0 != dia.1 { return dia.0 < dia.1 }
            if a.venda != b.venda { return !a.venda }
            return a.operacao.data < b.operacao.data
        }
    }

    var posicao: Posicao { Posicao(lancamentos()) }

    // Quanto dá para vender na data sem deixar esta venda nem as seguintes sem saldo:
    // a menor quantidade da data em diante, com uma venda de zero no lugar da nova.
    func maximoVenda(em data: Date, calendario: Calendar = .current) -> Double {
        let sonda = Operacao(quantidade: 0, preco: 0, data: data)
        var comSonda = self
        comSonda.vendas.append(sonda)
        var p = Posicao()
        var minimo: Double?
        for l in comSonda.lancamentos(calendario: calendario) {
            p.aplicar(l)
            if minimo != nil || l.id == sonda.id { minimo = min(minimo ?? p.quantidade, p.quantidade) }
        }
        return minimo ?? 0
    }

    // nil quando pode registrar. Data no futuro conta pelo dia: hoje a qualquer hora vale.
    func problema(venda: Bool, quantidade: Double, data: Date, agora: Date = .now, calendario: Calendar = .current) -> Problema? {
        if calendario.startOfDay(for: data) > agora { return .dataFutura }
        guard venda else { return nil }
        let maximo = maximoVenda(em: data, calendario: calendario)
        return quantidade > maximo + Posicao.folga(maximo) ? .semSaldo(disponivel: maximo) : nil
    }

    // Apagar uma compra não pode deixar venda sem saldo; venda sempre pode ser apagada.
    func podeApagar(_ operacao: Operacao) -> Bool {
        var resto = self
        resto.compras.removeAll { $0.id == operacao.id }
        return resto.compras.count == compras.count || !resto.posicao.semSaldo
    }
}

import Foundation

// Contas da Visão geral e do notch: o patrimônio ao longo do tempo (no dia e no último ano) e a alocação.
// Tudo aqui é puro, sem rede nem tela: Carteira junta os dados, e os testes conferem as contas.

// Valor de uma série num instante: o último ponto até ali; antes do primeiro, o primeiro (o preço de antes do
// pregão abrir é o do fechamento anterior, e o da série diária que ainda não começou, o mais antigo que há).
func valor(_ pontos: [Ponto], em instante: Date) -> Double? {
    guard let primeiro = pontos.first else { return nil }
    var resposta = primeiro.preco
    for p in pontos {
        if p.em > instante { break }
        resposta = p.preco
    }
    return resposta
}

// Uma posição para a soma no tempo: a série de preços (na moeda dela), quanto havia em cada instante e quanto
// custou o que havia (na moeda do custo); custo nil é saldo da Binance sem preço médio, fora da linha do investido.
struct PosicaoNoTempo {
    let serie: Serie
    let quantidade: (Date) -> Double
    let custo: (Date) -> (valor: Double, moeda: String)?
}

// Patrimônio e investido em cada instante, na moeda escolhida, pelo câmbio daquele instante (o último até ali).
// Instante sem câmbio para alguma posição fica de fora: melhor um buraco do que um ponto errado.
func patrimonioNoTempo(_ posicoes: [PosicaoNoTempo], cambio: [String: [Ponto]], moeda: String,
                       instantes: [Date]) -> (valor: [Ponto], investido: [Ponto]) {
    var valores: [Ponto] = []
    var investidos: [Ponto] = []
    instante: for t in instantes {
        let taxas = cambio.compactMapValues { valor($0, em: t) }
        var total = 0.0
        var investido = 0.0
        for p in posicoes {
            let q = p.quantidade(t)
            if q > 0 {
                guard let preco = valor(p.serie.pontos, em: t),
                      let v = converter(q * preco, de: p.serie.moeda, para: moeda, cambio: taxas) else { continue instante }
                total += v
            }
            if let c = p.custo(t), c.valor > 0 {
                guard let v = converter(c.valor, de: c.moeda, para: moeda, cambio: taxas) else { continue instante }
                investido += v
            }
        }
        valores.append(Ponto(em: t, preco: total))
        investidos.append(Ponto(em: t, preco: investido))
    }
    return (valores, investidos)
}

// Fim de cada um dos últimos `dias` dias (o de hoje é agora): o fechamento diário vale até o fim do dia dele.
func fimDosDias(_ dias: Int, ate agora: Date, calendario: Calendar = .current) -> [Date] {
    let hoje = calendario.startOfDay(for: agora)
    return (0..<dias).reversed().compactMap { atras in
        guard atras > 0 else { return agora }
        return calendario.date(byAdding: .day, value: 1 - atras, to: hoje).map { $0.addingTimeInterval(-1) }
    }
}

// Onde está o dinheiro: B3, bolsas de fora e cripto.
enum Classe: CaseIterable, Identifiable {
    case b3, cripto, exterior
    var id: Self { self }
}

extension Ativo {
    var classe: Classe { cripto ? .cripto : simboloYahoo.hasSuffix(".SA") ? .b3 : .exterior }
}

struct Fatia: Identifiable {
    let id: String
    let simbolo: String
    let classe: Classe
    let valor: Double
}

// Parte de cada classe no total, na ordem fixa das classes; classe vazia fica de fora.
func porClasse(_ fatias: [Fatia]) -> [(classe: Classe, valor: Double, parte: Double)] {
    let total = fatias.reduce(0) { $0 + $1.valor }
    guard total > 0 else { return [] }
    return Classe.allCases.compactMap { c in
        let v = fatias.filter { $0.classe == c }.reduce(0) { $0 + $1.valor }
        return v > 0 ? (c, v, v / total) : nil
    }
}

extension Fonte {
    // Fechamentos diários de um ano: ação pelo Yahoo, cripto pelas velas diárias da Binance (par em USDT; sem ele,
    // em reais). BRL e USDT têm preço fixo.
    static func historico(_ ativo: Ativo) async throws -> Serie {
        if ativo.cripto, let moeda = fixas[ativo.simbolo] {
            return Serie(moeda: moeda, pontos: [Ponto(em: .distantPast, preco: 1)])
        }
        guard ativo.cripto else { return try await chart(ativo.simboloYahoo, "range=1y&interval=1d").serie() }
        do {
            return Serie(velas: try await baixar(diarias(ativo.simbolo + "USDT")), moeda: "USD")
        } catch let erro as Falha where erro.codigo == -1121 {
            return Serie(velas: try await baixar(diarias(ativo.simbolo + "BRL")), moeda: "BRL")
        }
    }

    private static func diarias(_ par: String) -> String {
        "https://api.binance.com/api/v3/klines?symbol=\(par)&interval=1d&limit=366"
    }
}

extension Carteira {
    // Cada posição pelo valor de hoje na moeda escolhida, para a alocação. Vazia sem total (falta câmbio).
    var fatias: [Fatia] {
        guard total != nil else { return [] }
        return (linhas + linhasBinance).filter { $0.quantidade > 0 && $0.cotacao != nil }.compactMap { l in
            let v = resumo(l).patrimonio
            return v > 0 ? Fatia(id: l.id, simbolo: l.ativo.simbolo, classe: l.ativo.classe, valor: v) : nil
        }
    }

    // O patrimônio de hoje, pelo minigráfico de cada posição e o câmbio de agora; termina no total de agora.
    var patrimonioDoDia: [Ponto] {
        guard let total else { return [] }
        let posicoes = (linhas + linhasBinance).filter { $0.quantidade > 0 }.compactMap { l -> PosicaoNoTempo? in
            guard let c = l.cotacao else { return nil }
            return PosicaoNoTempo(serie: Serie(moeda: c.moeda, pontos: serie(l) ?? [Ponto(em: c.em, preco: c.preco)]),
                                  quantidade: { _ in l.quantidade }, custo: { _ in nil })
        }
        let cambio = snapshot.cambio.mapValues { [Ponto(em: .distantPast, preco: $0)] }
        let instantes = Set(posicoes.flatMap { $0.serie.pontos.map(\.em) }).filter { $0 < .now }.sorted()
        return patrimonioNoTempo(posicoes, cambio: cambio, moeda: total.moeda, instantes: instantes).valor
            + [Ponto(em: .now, preco: total.patrimonio)]
    }

    // Patrimônio e investido nos últimos `dias` dias, um ponto por dia, terminando no total de agora. As compras e
    // vendas valem a partir da data delas; o saldo da Binance, que o app só conhece hoje, vale como sempre igual.
    func patrimonioHistorico(dias: Int) -> (valor: [Ponto], investido: [Ponto])? {
        guard let total, !historico.isEmpty else { return nil }
        let precoMedio = self.precoMedio
        let posicoes = posicoesDoHistorico.compactMap { l -> PosicaoNoTempo? in
            guard let serie = historico[l.ativo.id] else { return nil }
            if l.binance {
                let custo = precoMedio[l.ativo.simbolo].map { (valor: $0 * l.quantidade, moeda: "BRL") }
                return PosicaoNoTempo(serie: serie, quantidade: { _ in l.quantidade }, custo: { _ in custo })
            }
            let lancamentos = l.ativo.lancamentos()
            let ate = { (t: Date) in Posicao(lancamentos.filter { $0.operacao.data <= t }) }
            return PosicaoNoTempo(serie: serie, quantidade: { ate($0).quantidade },
                                  custo: { t in (ate(t).custo, l.moedaCusto) })
        }
        let r = patrimonioNoTempo(posicoes, cambio: historicoCambio, moeda: total.moeda,
                                  instantes: fimDosDias(dias, ate: .now).dropLast())
        return (r.valor + [Ponto(em: .now, preco: total.patrimonio)], r.investido + [Ponto(em: .now, preco: total.custo)])
    }
}

import Charts
import SwiftUI

// Visão geral: os números da carteira, o patrimônio no tempo, a alocação, o dia de cada ativo e a lista de desejos.

// Cores de dado: slots 1 a 3 da paleta categórica validada (fixos, nunca girados), um tom para cada aparência.
// O valor do patrimônio usa o slot 1; alta e baixa seguem o verde e o vermelho do resto do app.
extension Color {
    init(claro: UInt32, escuro: UInt32) {
        let cor = { (hex: UInt32) in
            NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(nsColor: NSColor(name: nil) { a in a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? cor(escuro) : cor(claro) })
    }

    static let azulDados = Color(claro: 0x2A78D6, escuro: 0x3987E5)
    // A linha do patrimônio segue o tema; no Padrão, o azul validado da paleta.
    @MainActor static var serie1: Color { Ajustes.atual.tema.estilo.linha }
}

extension Classe {
    @MainActor var nome: String {
        switch self {
        case .b3: tr("Ações B3", "B3 stocks")
        case .cripto: tr("Cripto", "Crypto")
        case .exterior: tr("Ações exterior", "Foreign stocks")
        }
    }

    var cor: Color {
        switch self {
        case .b3: .azulDados
        case .cripto: Color(claro: 0xEB6834, escuro: 0xD95926)
        case .exterior: Color(claro: 0x1BAF7A, escuro: 0x199E70)
        }
    }
}

// Uma faixa só, dividida pelas classes, com a legenda embaixo (cor nunca sozinha: nome e percentual junto).
struct FaixaAlocacao: View {
    let classes: [(classe: Classe, valor: Double, parte: Double)]
    var altura: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(classes, id: \.classe) { c in
                        RoundedRectangle(cornerRadius: altura / 2, style: .continuous)
                            .fill(c.classe.cor)
                            .frame(width: max(2, (g.size.width - CGFloat(classes.count - 1) * 2) * c.parte))
                    }
                }
            }
            .frame(height: altura)
            HStack(spacing: 12) {
                ForEach(classes, id: \.classe) { c in
                    HStack(spacing: 4) {
                        Circle().fill(c.classe.cor).frame(width: 7, height: 7)
                        Text(c.classe.nome).foregroundStyle(.secondary)
                        Text(c.parte.formatted(.percent.precision(.fractionLength(0)).locale(Ajustes.atual.idioma.locale)))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .monospacedDigit()
        }
    }
}

// Linha do patrimônio de hoje, sem eixos: verde ou vermelha pelo dia. Decorativa para o VoiceOver (o número do lado
// já diz o valor e o dia).
struct MiniPatrimonio: View {
    let pontos: [Ponto]

    var body: some View {
        let subiu = (pontos.last?.preco ?? 0) >= (pontos.first?.preco ?? 0)
        Chart(Array(pontos.enumerated()), id: \.offset) { _, p in
            LineMark(x: .value("Hora", p.em), y: .value("Valor", p.preco))
                .foregroundStyle(subiu ? Color.green : .red)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}

struct VisaoGeralTela: View {
    @Environment(Carteira.self) private var carteira
    @State private var periodo: Periodo = .dia
    @State private var selecionado: Date?

    enum Periodo: Int, CaseIterable, Identifiable {
        case dia = 1, semana = 7, mes = 31, semestre = 183, ano = 366
        var id: Self { self }

        @MainActor var rotulo: String {
            switch self {
            case .dia: tr("1D", "1D")
            case .semana: tr("1S", "1W")
            case .mes: "1M"
            case .semestre: "6M"
            case .ano: tr("1A", "1Y")
            }
        }
    }

    var body: some View {
        Group {
            if carteira.posicoesDoHistorico.isEmpty && carteira.linhas.isEmpty {
                ContentUnavailableView(tr("Nada para mostrar ainda", "Nothing to show yet"), systemImage: "chart.pie",
                                       description: Text(tr("Adicione ativos na Carteira ou conecte a Binance.", "Add assets in Portfolio or connect Binance.")))
            } else {
                ScrollView {
                    if estilo.layout == .editorial { editorial } else { grade }
                }
            }
        }
        .navigationTitle(tr("Visão geral", "Overview"))
        .task { await carteira.carregarHistorico() }
        .task(id: desejos.map(\.id)) {
            for l in desejos { await carteira.carregarIndicadores(l.ativo) }
        }
    }

    private var estilo: EstiloVisual { Ajustes.atual.tema.estilo }
    private var compacto: Bool { estilo.layout == .compacto }

    // Cartões (o padrão) e compacto (denso: tudo menor, mais junto).
    private var grade: some View {
        VStack(alignment: .leading, spacing: estilo.espaco) {
            if let total = carteira.total {
                numeros(total)
            } else if let aviso = carteira.avisoTotal {
                Label(aviso, systemImage: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
            }
            cartao(tr("Patrimônio", "Portfolio value")) { patrimonio }
            HStack(alignment: .top, spacing: estilo.espaco) {
                cartao(tr("Alocação por classe", "Allocation by class")) {
                    FaixaAlocacao(classes: porClasse(carteira.fatias), altura: compacto ? 8 : 14)
                }
                cartao(tr("Alocação por ativo", "Allocation by asset")) { alocacao }
            }
            HStack(alignment: .top, spacing: estilo.espaco) {
                cartao(tr("Hoje", "Today")) { hoje }
                cartao(tr("Resultado em aberto", "Unrealized gain")) { resultados }
            }
            if !desejos.isEmpty { cartao(tr("Lista de desejos", "Wishlist")) { listaDeDesejos } }
        }
        .padding(compacto ? 12 : 20)
    }

    // Editorial: o patrimônio em número grande, as seções corridas e separadas por fios, sem cartões.
    private var editorial: some View {
        VStack(alignment: .leading, spacing: estilo.espaco) {
            if let t = carteira.total {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Patrimônio", "Portfolio value").uppercased()).font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
                    Text(valor: dinheiro(t.patrimonio, t.moeda))
                        .font(.system(size: 46, weight: .semibold, design: estilo.fonteTitulo))
                        .monospacedDigit()
                    HStack(spacing: 18) {
                        resumoEditorial(tr("Hoje", "Today"), dinheiro(t.hoje, t.moeda, sinal: true) + " (\(pct(t.hojePct)))", cor(t.hoje))
                        if t.custo > 0 {
                            resumoEditorial(tr("Em aberto", "Unrealized"), dinheiro(t.aberto.lucro, t.moeda, sinal: true) + " (\(pct(t.aberto.percentual)))", cor(t.aberto.lucro))
                            resumoEditorial(tr("Investido", "Invested"), dinheiro(t.custo, t.moeda), .primary)
                        }
                        if t.realizado != 0 { resumoEditorial(tr("Realizado", "Realized"), dinheiro(t.realizado, t.moeda, sinal: true), cor(t.realizado)) }
                    }
                }
            } else if let aviso = carteira.avisoTotal {
                Label(aviso, systemImage: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
            }
            secao(tr("Patrimônio no tempo", "Value over time")) { patrimonio }
            Divider()
            HStack(alignment: .top, spacing: 40) {
                secao(tr("Alocação por classe", "Allocation by class")) { FaixaAlocacao(classes: porClasse(carteira.fatias), altura: 10) }
                secao(tr("Alocação por ativo", "Allocation by asset")) { alocacao }
            }
            Divider()
            HStack(alignment: .top, spacing: 40) {
                secao(tr("Hoje", "Today")) { hoje }
                secao(tr("Resultado em aberto", "Unrealized gain")) { resultados }
            }
            if !desejos.isEmpty {
                Divider()
                secao(tr("Lista de desejos", "Wishlist")) { listaDeDesejos }
            }
        }
        .padding(32)
    }

    private func resumoEditorial(_ rotulo: String, _ valor: String, _ cor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rotulo).font(.caption).foregroundStyle(.secondary)
            Text(valor: valor).font(.callout.weight(.medium)).foregroundStyle(cor).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func secao<Conteudo: View>(_ titulo: String, @ViewBuilder _ conteudo: () -> Conteudo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(titulo).font(.system(size: 20, weight: .semibold, design: estilo.fonteTitulo))
            conteudo()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Números

    private func numeros(_ t: Total) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: compacto ? 140 : 170), spacing: estilo.espaco)], spacing: estilo.espaco) {
            numero(tr("Patrimônio", "Portfolio value"), dinheiro(t.patrimonio, t.moeda), destaque: true)
            numero(tr("Hoje", "Today"), dinheiro(t.hoje, t.moeda, sinal: true), detalhe: pct(t.hojePct), cor: cor(t.hoje))
            numero(tr("Em aberto", "Unrealized"), t.custo > 0 ? dinheiro(t.aberto.lucro, t.moeda, sinal: true) : "—",
                   detalhe: t.custo > 0 ? pct(t.aberto.percentual) : nil, cor: cor(t.aberto.lucro))
            numero(tr("Realizado", "Realized"), t.realizado != 0 ? dinheiro(t.realizado, t.moeda, sinal: true) : "—", cor: cor(t.realizado))
            numero(tr("Investido", "Invested"), t.custo > 0 ? dinheiro(t.custo, t.moeda) : "—")
        }
    }

    private func numero(_ rotulo: String, _ valor: String, detalhe: String? = nil, cor: Color = .primary, destaque: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(compacto ? rotulo.uppercased() : rotulo).font(compacto ? .caption2.weight(.semibold) : .caption).foregroundStyle(.secondary)
            Text(valor: valor)
                .font(.system(size: (destaque ? 24 : 18) - (compacto ? 5 : 0), weight: .semibold, design: estilo.fonteTitulo))
                .foregroundStyle(destaque ? .primary : cor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detalhe { Text(detalhe).font(.caption).foregroundStyle(cor) }
        }
        .monospacedDigit()
        .padding(compacto ? 10 : estilo.respiro - 2)
        .frame(maxWidth: .infinity, minHeight: compacto ? 58 : 78, alignment: .topLeading)
        .modifier(FundoCartao())
        .accessibilityElement(children: .combine)
    }

    // MARK: Patrimônio no tempo

    private var dados: (valor: [Ponto], investido: [Ponto])? {
        guard periodo != .dia else {
            let dia = carteira.patrimonioDoDia
            guard dia.count > 1, let custo = carteira.total?.custo, custo > 0 else { return dia.isEmpty ? nil : (dia, []) }
            return (dia, [Ponto(em: dia[0].em, preco: custo), Ponto(em: dia[dia.count - 1].em, preco: custo)])
        }
        // Os dias antes da primeira compra (tudo zero) ficam de fora: o gráfico começa quando havia patrimônio.
        guard let h = carteira.patrimonioHistorico(dias: periodo.rawValue) else { return nil }
        let inicio = h.valor.indices.first { h.valor[$0].preco > 0 || h.investido[$0].preco > 0 } ?? 0
        return (Array(h.valor.dropFirst(inicio)), Array(h.investido.dropFirst(inicio)))
    }

    @ViewBuilder private var patrimonio: some View {
        let moeda = carteira.total?.moeda ?? carteira.moeda
        let privacidade = Ajustes.atual.privacidade
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // Duas séries: legenda sempre, com o traço de cada uma.
                legenda(tr("Patrimônio", "Value"), cor: .serie1, tracejado: false)
                legenda(tr("Investido", "Invested"), cor: .secondary, tracejado: true)
                Spacer()
                Picker(tr("Período", "Period"), selection: $periodo) {
                    ForEach(Periodo.allCases) { Text($0.rotulo).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
            }
            if let d = dados, d.valor.count > 1 {
                // A área começa logo abaixo do menor valor: desde o zero, ela achataria a linha e o eixo iria a zero.
                let todos = (d.valor + d.investido).map(\.preco)
                let (minimo, maximo) = (todos.min() ?? 0, todos.max() ?? 0)
                let base = max(0, minimo - max((maximo - minimo) * 0.15, minimo * 0.005))
                Chart {
                    ForEach(d.valor, id: \.em) { p in
                        AreaMark(x: .value("Data", p.em), yStart: .value("Base", base), yEnd: .value("Valor", p.preco))
                            .foregroundStyle(LinearGradient(colors: [Color.serie1.opacity(0.22), Color.serie1.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(estilo.interpolacao)
                        LineMark(x: .value("Data", p.em), y: .value("Valor", p.preco), series: .value("Série", "valor"))
                            .foregroundStyle(Color.serie1)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(estilo.interpolacao)
                    }
                    ForEach(d.investido, id: \.em) { p in
                        LineMark(x: .value("Data", p.em), y: .value("Valor", p.preco), series: .value("Série", "investido"))
                            .foregroundStyle(Color.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .interpolationMethod(.stepEnd)
                    }
                    if let s = selecionado, let p = maisProximo(d.valor, de: s) {
                        RuleMark(x: .value("Data", p.em)).foregroundStyle(Color.secondary.opacity(0.35))
                        PointMark(x: .value("Data", p.em), y: .value("Valor", p.preco))
                            .foregroundStyle(Color.serie1)
                            .symbolSize(70)
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                dica(p, investido: maisProximo(d.investido, de: p.em), moeda: moeda)
                            }
                    }
                }
                .chartXSelection(value: $selecionado)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    if !privacidade {
                        AxisMarks { v in
                            AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                            AxisValueLabel { if let n = v.as(Double.self) { Text(compacto(n, moeda: moeda)) } }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel(format: periodo == .dia ? .dateTime.hour().minute() : .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: compacto ? 170 : 230)
                .accessibilityLabel(tr("Gráfico do patrimônio", "Portfolio value chart"))
            } else if periodo != .dia && carteira.historico.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(tr("Buscando o histórico…", "Loading history…")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 230)
            } else {
                Text(tr("Sem dados suficientes para este período.", "Not enough data for this period."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 230)
            }
            nota
        }
    }

    @ViewBuilder private var nota: some View {
        let semHistorico = carteira.semHistorico.joined(separator: ", ")
        let texto = periodo == .dia
            ? tr("Hoje, pelos preços do dia de cada ativo e o câmbio de agora.", "Today, from each asset's intraday prices and the current exchange rate.")
            : tr("Fechamento de cada dia, contando o que você tinha naquela data (compras e vendas pela data delas). Saldos da Binance contam como se fossem os de hoje em todo o período.",
                 "Each day's close, counting what you held on that date (purchases and sales by their dates). Binance balances count as today's for the whole period.")
            + (semHistorico.isEmpty ? "" : tr(" Sem histórico: \(semHistorico).", " No history: \(semHistorico)."))
        Text(texto).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func legenda(_ texto: String, cor: Color, tracejado: Bool) -> some View {
        HStack(spacing: 5) {
            Path { p in p.move(to: CGPoint(x: 0, y: 4)); p.addLine(to: CGPoint(x: 16, y: 4)) }
                .stroke(cor, style: StrokeStyle(lineWidth: 2, dash: tracejado ? [4, 3] : []))
                .frame(width: 16, height: 8)
            Text(texto).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func dica(_ p: Ponto, investido: Ponto?, moeda: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(periodo == .dia ? quando(p.em, hora: .shortened) : quando(p.em, data: .abbreviated))
                .font(.caption2).foregroundStyle(.secondary)
            Text(valor: dinheiro(p.preco, moeda)).font(.callout.weight(.semibold))
            if let i = investido, i.preco > 0 {
                let r = resultado(custo: i.preco, valor: p.preco)
                Text(valor: tr("Investido \(dinheiro(i.preco, moeda))", "Invested \(dinheiro(i.preco, moeda))"))
                    .font(.caption2).foregroundStyle(.secondary)
                Text(valor: "\(dinheiro(r.lucro, moeda, sinal: true)) (\(pct(r.percentual)))").font(.caption2).foregroundStyle(cor(r.lucro))
            }
        }
        .monospacedDigit()
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func maisProximo(_ pontos: [Ponto], de instante: Date) -> Ponto? {
        pontos.min { abs($0.em.timeIntervalSince(instante)) < abs($1.em.timeIntervalSince(instante)) }
    }

    // MARK: Alocação, hoje e resultado: barras horizontais com o número escrito ao lado (rótulo direto).

    private var alocacao: some View {
        let fatias = carteira.fatias.sorted { $0.valor > $1.valor }
        let total = fatias.reduce(0) { $0 + $1.valor }
        // Até 8 barras; o resto vira "Outros".
        let mostradas = Array(fatias.prefix(7)) + (fatias.count > 8
            ? [Fatia(id: "outros", simbolo: tr("Outros", "Other"), classe: .cripto, valor: fatias.dropFirst(7).reduce(0) { $0 + $1.valor })]
            : Array(fatias.dropFirst(7)))
        let maior = mostradas.map(\.valor).max() ?? 1
        let percentual = { (v: Double) in (v / max(total, 1e-9)).formatted(.percent.precision(.fractionLength(0)).locale(Ajustes.atual.idioma.locale)) }
        // Linhas simples (nome, barra, percentual): a barra mede contra o maior, o texto diz a parte do total.
        return VStack(spacing: 8) {
            ForEach(mostradas) { f in
                HStack(spacing: 8) {
                    Text(f.simbolo).font(.callout).frame(width: 64, alignment: .leading).lineLimit(1)
                    GeometryReader { g in
                        UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                            .fill(f.id == "outros" ? Color.secondary : f.classe.cor)
                            .frame(width: max(2, g.size.width * f.valor / maior), height: 12)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 16)
                    Text(percentual(f.valor)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // A variação do dia de cada ativo, da maior alta à maior baixa: barra para a direita sobe, para a esquerda cai.
    private var hoje: some View {
        let linhas = (carteira.linhas + carteira.linhasBinance).filter { $0.cotacao != nil && !$0.desejo }
            .sorted { ($0.cotacao?.variacao ?? 0) > ($1.cotacao?.variacao ?? 0) }
        return barrasDivergentes(linhas.map { ($0.id, $0.ativo.simbolo, $0.cotacao?.variacao ?? 0) }) { pct($0) }
    }

    // Quanto cada posição com custo ganha ou perde agora, na moeda escolhida.
    private var resultados: some View {
        let itens = (carteira.linhas + carteira.linhasBinance).compactMap { l -> (String, String, Double)? in
            let r = carteira.resumo(l)
            return r.custo > 0 && l.quantidade > 0 ? (l.id, l.ativo.simbolo, r.aberto.lucro) : nil
        }
        .sorted { $0.2 > $1.2 }
        let moeda = carteira.total?.moeda ?? carteira.moeda
        return Group {
            if itens.isEmpty {
                Text(tr("Registre compras (ou o preço médio da Binance) para ver o resultado de cada ativo.",
                        "Record purchases (or Binance average prices) to see each asset's gain."))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                barrasDivergentes(itens) { dinheiro($0, moeda, sinal: true) }
            }
        }
    }

    private func barrasDivergentes(_ itens: [(id: String, simbolo: String, valor: Double)], texto: @escaping (Double) -> String) -> some View {
        Chart(itens, id: \.id) { i in
            BarMark(x: .value("Valor", i.valor), y: .value("Ativo", i.simbolo), height: .fixed(14))
                .foregroundStyle(cor(i.valor))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .annotation(position: i.valor >= 0 ? .trailing : .leading) {
                    Text(valor: texto(i.valor)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            RuleMark(x: .value("Zero", 0)).foregroundStyle(Color.secondary.opacity(0.4))
        }
        .chartXAxis(.hidden)
        .chartXScale(range: .plotDimension(padding: 60))
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisValueLabel() } }
        .frame(height: CGFloat(max(itens.count, 1)) * 26)
    }

    // MARK: Lista de desejos

    private var desejos: [Linha] { carteira.linhas.filter(\.desejo) }

    private var listaDeDesejos: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            ForEach(desejos) { l in
                HStack(spacing: 10) {
                    Monograma(ativo: l.ativo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.ativo.simbolo).fontWeight(.semibold)
                        if let c = l.cotacao { Text(dinheiro(c.preco, c.moeda, oculto: false)).font(.callout).monospacedDigit() }
                        if let i = carteira.indicadores[l.ativo.id], let maxima = i.fiftyTwoWeekHigh, let c = l.cotacao, maxima > 0 {
                            let abaixo = 1 - c.preco / maxima
                            Text(abaixo > 0.005
                                 ? tr("\(pct(abaixo, sinal: false)) abaixo da máx. de 52 sem.", "\(pct(abaixo, sinal: false)) below the 52-wk high")
                                 : tr("Na máxima de 52 semanas", "At the 52-week high"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    if let c = l.cotacao { Pilula(fracao: c.variacao) }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Peças

    private func cartao<Conteudo: View>(_ titulo: String, @ViewBuilder _ conteudo: () -> Conteudo) -> some View {
        VStack(alignment: .leading, spacing: compacto ? 8 : 12) {
            Text(compacto ? titulo.uppercased() : titulo)
                .font(compacto ? .caption.weight(.semibold) : .system(.headline, design: estilo.fonteTitulo))
                .foregroundStyle(compacto ? .secondary : .primary)
            conteudo()
        }
        .padding(estilo.respiro)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .modifier(FundoCartao())
    }

    // 1.234.567 → "R$ 1,2 mi" no eixo, onde não cabe o valor inteiro.
    private func compacto(_ v: Double, moeda: String) -> String {
        v.formatted(.currency(code: moeda).notation(.compactName).precision(.fractionLength(0...1)).locale(Ajustes.atual.idioma.locale))
    }
}

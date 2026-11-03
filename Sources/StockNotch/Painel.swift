import SwiftUI

struct PainelView: View {
    enum Secao: CaseIterable, Identifiable {
        case carteira, binance, ajustes
        var id: Self { self }

        var icone: String {
            switch self {
            case .carteira: "briefcase"
            case .binance: "link"
            case .ajustes: "gearshape"
            }
        }

        @MainActor var nome: String {
            switch self {
            case .carteira: tr("Carteira", "Portfolio")
            case .binance: "Binance"
            case .ajustes: tr("Ajustes", "Settings")
            }
        }
    }

    @State private var secao: Secao? = .carteira

    var body: some View {
        NavigationSplitView {
            List(Secao.allCases, selection: $secao) { s in
                Label(s.nome, systemImage: s.icone).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) {
                Button { NSApp.terminate(nil) } label: {
                    Label(tr("Sair do StockNotch", "Quit StockNotch"), systemImage: "power")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        } detail: {
            switch secao ?? .carteira {
            case .carteira: CarteiraTela()
            case .binance: BinanceTela()
            case .ajustes: AjustesTela()
            }
        }
        .frame(minWidth: 880, minHeight: 480)
        // Controles nativos (DatePicker etc.) seguem o idioma do app, não o do sistema.
        .environment(\.locale, Ajustes.atual.idioma.locale)
    }
}

struct CarteiraTela: View {
    @Environment(Carteira.self) private var carteira
    @State private var selecao: Ativo.ID?
    @State private var adicionando = false
    @State private var registrando: Registro?
    @State private var vendoOperacoes: Ativo?
    @State private var removendo: Ativo?

    private var selecionado: Ativo? { carteira.ativos.first { $0.id == selecao } }

    var body: some View {
        Group {
            if carteira.ativos.isEmpty {
                ContentUnavailableView {
                    Label(tr("Nenhum ativo", "No assets"), systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text(tr("Adicione ações da B3, dos EUA ou criptomoedas para acompanhar no notch.",
                            "Add B3 or US stocks or crypto to follow them in the notch."))
                } actions: {
                    Button(tr("Adicionar ativo", "Add Asset")) { adicionando = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                tabela
            }
        }
        .navigationTitle(tr("Carteira", "Portfolio"))
        .toolbar {
            ToolbarItem {
                Button { adicionando = true } label: { Label(tr("Adicionar ativo", "Add Asset"), systemImage: "plus") }
                    .help(tr("Adicionar ação ou cripto", "Add a stock or crypto"))
            }
            ToolbarItem {
                Button { vendoOperacoes = selecionado } label: { Label(tr("Operações", "Transactions"), systemImage: "list.bullet.rectangle") }
                    .help(tr("Ver compras e vendas do ativo selecionado (ou dê dois cliques na linha)",
                             "See the selected asset's purchases and sales (or double-click the row)"))
                    .disabled(selecionado == nil)
            }
        }
        .sheet(isPresented: $adicionando) { FormAdicionar(fixo: nil).environment(carteira) }
        .sheet(item: $registrando) { FormAdicionar(fixo: $0.ativo, venda: $0.venda).environment(carteira) }
        .sheet(item: $vendoOperacoes) { OperacoesFolha(id: $0.id).environment(carteira) }
        .confirmationDialog(tr("Remover \(removendo?.simbolo ?? "")?", "Remove \(removendo?.simbolo ?? "")?"),
                            isPresented: .init(get: { removendo != nil }, set: { if !$0 { removendo = nil } }),
                            presenting: removendo) { ativo in
            Button(tr("Remover", "Remove"), role: .destructive) { carteira.remover(ativo) }
        } message: { ativo in
            let n = ativo.compras.count + ativo.vendas.count
            Text(tr("O histórico de \(n) operação(ões) será apagado.", "The history of \(n) transaction(s) will be deleted."))
        }
    }

    private var tabela: some View {
        Table(carteira.linhas, selection: $selecao) {
            TableColumn(tr("Ativo", "Asset")) { l in
                HStack(spacing: 8) {
                    Monograma(ativo: l.ativo, tamanho: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(l.ativo.simbolo).fontWeight(.semibold)
                        Text(l.ativo.cripto ? tr("Cripto", "Crypto") : tr("Ação", "Stock")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .width(min: 100, ideal: 120)
            TableColumn(tr("Quantidade", "Quantity")) { l in
                Text(l.quantidade > 0 ? qtd(l.quantidade) : "—")
            }
            .width(min: 60, ideal: 70)
            .alignment(.trailing)
            // Preço médio na moeda das compras e cotação na do ativo; valor e resultado na moeda escolhida.
            TableColumn(tr("Preço médio", "Avg. Price")) { l in
                Text(l.quantidade > 0 ? dinheiro((l.custo ?? 0) / l.quantidade, l.moedaCusto) : "—")
            }
            .width(min: 80, ideal: 100)
            .alignment(.trailing)
            TableColumn(tr("Cotação", "Price")) { l in
                if let c = l.cotacao {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(dinheiro(c.preco, c.moeda))
                        SeloCotacao(cotacao: c, agora: carteira.agora).font(.caption).foregroundStyle(.secondary)
                    }
                } else if carteira.falhas.contains(l.ativo.id) {
                    Text(tr("sem cotação", "no quote")).foregroundStyle(.secondary)
                } else {
                    Text(carteira.faltaCambio(l) ? tr("sem câmbio", "no exchange rate") : "…").foregroundStyle(.secondary)
                }
            }
            .width(min: 90, ideal: 120)
            .alignment(.trailing)
            TableColumn(tr("Dia", "Day")) { l in
                if let c = l.cotacao { Pilula(fracao: c.variacao) }
            }
            .width(min: 70, ideal: 80)
            .alignment(.trailing)
            // Valor, em aberto e realizado pela mesma conta do total do notch (resumo → somar).
            TableColumn(tr("Valor", "Value")) { l in
                let r = carteira.resumo(l)
                if l.cotacao != nil, l.quantidade > 0 {
                    Text(dinheiro(r.patrimonio, r.moeda))
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 110)
            .alignment(.trailing)
            TableColumn(tr("Em aberto", "Unrealized")) { l in
                let r = carteira.resumo(l)
                if r.custo > 0 {
                    TextoResultado(resultado: r.aberto, moeda: r.moeda)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 110, ideal: 150)
            .alignment(.trailing)
            TableColumn(tr("Realizado", "Realized")) { l in
                let r = carteira.resumo(l)
                if r.realizado != 0 {
                    TextoResultado(resultado: Resultado(lucro: r.realizado, percentual: 0), moeda: r.moeda, comPercentual: false)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 100)
            .alignment(.trailing)
        }
        .monospacedDigit()
        .contextMenu(forSelectionType: Ativo.ID.self) { ids in
            if let ativo = carteira.ativos.first(where: { $0.id == ids.first }) {
                Button(tr("Ver operações…", "View Transactions…")) { vendoOperacoes = ativo }
                Button(tr("Registrar compra…", "Record Purchase…")) { registrando = Registro(ativo: ativo, venda: false) }
                Button(tr("Registrar venda…", "Record Sale…")) { registrando = Registro(ativo: ativo, venda: true) }
                    .disabled(ativo.posicao.quantidade <= 0)
                Divider()
                Button(tr("Remover \(ativo.simbolo)", "Remove \(ativo.simbolo)"), role: .destructive) {
                    if ativo.compras.isEmpty && ativo.vendas.isEmpty { carteira.remover(ativo) } else { removendo = ativo }
                }
            }
        } primaryAction: { ids in
            vendoOperacoes = carteira.ativos.first { $0.id == ids.first }
        }
    }
}

// Qual formulário abrir: compra ou venda de um ativo.
struct Registro: Identifiable {
    let ativo: Ativo
    let venda: Bool
    var id: String { ativo.id + (venda ? ":venda" : ":compra") }
}

struct OperacoesFolha: View {
    @Environment(Carteira.self) private var carteira
    @Environment(\.dismiss) private var dismiss
    let id: Ativo.ID
    @State private var registrando: Registro?

    var body: some View {
        // Lê da carteira a cada mudança: apagar ou registrar atualiza a lista na hora.
        let ativo = carteira.ativos.first { $0.id == id }
        let moeda = carteira.linhas.first { $0.ativo.id == id }?.moedaCusto ?? "BRL"
        let lancamentos = Array((ativo?.lancamentos() ?? []).reversed())  // mais recentes primeiro
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let ativo { Monograma(ativo: ativo, tamanho: 30) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(ativo?.simbolo ?? "").font(.title3.weight(.semibold))
                    Text(tr("Compras e vendas registradas", "Recorded purchases and sales")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 8)

            Table(lancamentos) {
                TableColumn(tr("Tipo", "Type")) { l in
                    Label(l.venda ? tr("Venda", "Sale") : tr("Compra", "Purchase"), systemImage: l.venda ? "arrow.up.forward" : "cart")
                }
                .width(min: 80, ideal: 90)
                TableColumn(tr("Data", "Date")) { l in
                    Text(quando(l.operacao.data, data: .abbreviated))
                }
                .width(min: 90, ideal: 110)
                TableColumn(tr("Quantidade", "Quantity")) { l in
                    Text(qtd(l.operacao.quantidade))
                }
                .alignment(.trailing)
                TableColumn(tr("Preço", "Price")) { l in
                    Text(dinheiro(l.operacao.preco, moeda))
                }
                .alignment(.trailing)
                TableColumn("Total") { l in
                    Text(dinheiro(l.operacao.quantidade * l.operacao.preco, moeda))
                }
                .alignment(.trailing)
                TableColumn("") { l in
                    let pode = ativo?.podeApagar(l.operacao) ?? false
                    let dia = quando(l.operacao.data, data: .numeric)
                    Button { if let ativo { carteira.remover(l.operacao, de: ativo) } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .disabled(!pode)
                        .help(!pode ? tr("Apague antes as vendas que dependem desta compra", "Delete the sales that depend on this purchase first")
                              : l.venda ? tr("Apagar esta venda", "Delete this sale") : tr("Apagar esta compra", "Delete this purchase"))
                        .accessibilityLabel(l.venda ? tr("Apagar venda de \(dia)", "Delete sale from \(dia)")
                                            : tr("Apagar compra de \(dia)", "Delete purchase from \(dia)"))
                }
                .width(28)
            }
            .monospacedDigit()
            .overlay {
                if lancamentos.isEmpty {
                    ContentUnavailableView(tr("Sem operações", "No Transactions"), systemImage: "cart",
                                           description: Text(tr("Registre uma compra para ver o lucro ou prejuízo.",
                                                                "Record a purchase to see your gain or loss.")))
                }
            }

            HStack {
                Button(tr("Fechar", "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(tr("Registrar venda", "Record Sale")) { if let ativo { registrando = Registro(ativo: ativo, venda: true) } }
                    .disabled((ativo?.posicao.quantidade ?? 0) <= 0)
                Button { if let ativo { registrando = Registro(ativo: ativo, venda: false) } } label: {
                    Label(tr("Registrar compra", "Record Purchase"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(ativo == nil)
            }
            .padding(20)
        }
        .frame(width: 640, height: 440)
        .sheet(item: $registrando) { FormAdicionar(fixo: $0.ativo, venda: $0.venda).environment(carteira) }
    }
}

struct BinanceTela: View {
    @Environment(Carteira.self) private var carteira
    @State private var chave = ""
    @State private var segredo = ""
    @State private var conectando = false
    @State private var erro: (any Error)?

    var body: some View {
        Form {
            Section {
                LabeledContent(tr("Status", "Status")) {
                    if carteira.binanceConectada {
                        Label(tr("Conectada", "Connected"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label(tr("Não conectada", "Not connected"), systemImage: "circle.dashed").foregroundStyle(.secondary)
                    }
                }
                if carteira.binanceConectada {
                    Button(tr("Desconectar", "Disconnect"), role: .destructive) { carteira.desconectarBinance() }
                } else {
                    TextField("API Key", text: $chave, prompt: Text(tr("Cole a API Key", "Paste the API Key")))
                    SecureField("Secret Key", text: $segredo, prompt: Text(tr("Cole a Secret Key", "Paste the Secret Key")))
                    HStack {
                        Spacer()
                        if conectando { ProgressView().controlSize(.small) }
                        Button(tr("Conectar", "Connect")) { Task { await conectar() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(chave.isEmpty || segredo.isEmpty || conectando)
                    }
                }
                if let aviso = erro ?? carteira.erroBinance {
                    Label(mensagem(aviso), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            } header: {
                Text(tr("Conta", "Account"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Na Binance, crie uma chave de API deixando marcado só “Ativar leitura”. O app recusa chaves que podem negociar, transferir ou sacar, e guarda a Secret Key nas Chaves do macOS (Keychain).",
                            "On Binance, create an API key with only “Enable Reading” checked. The app refuses keys that can trade, transfer or withdraw, and stores the Secret Key in the macOS Keychain."))
                    Link(tr("Abrir o gerenciamento de API da Binance", "Open Binance API Management"),
                         destination: URL(string: tr("https://www.binance.com/pt-BR/my/settings/api-management",
                                                     "https://www.binance.com/en/my/settings/api-management"))!)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if carteira.binanceConectada {
                Section(tr("Saldos (spot e Simple Earn flexível)", "Balances (spot and Simple Earn Flexible)")) {
                    if carteira.linhasBinance.isEmpty {
                        let poeira = carteira.moeda == "USD" ? "USD" : "BRL"  // a moeda da cotação de cripto (ver linhasDeSaldo)
                        Text(carteira.atualizadoEm == nil ? tr("Carregando…", "Loading…")
                             : tr("Nenhum saldo acima de \(dinheiro(1, poeira)).", "No balances above \(dinheiro(1, poeira))."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(carteira.linhasBinance) { l in
                        HStack(spacing: 10) {
                            Monograma(ativo: l.ativo, tamanho: 22)
                            Text(l.ativo.simbolo).fontWeight(.semibold)
                            Spacer()
                            Text(qtd(l.quantidade)).foregroundStyle(.secondary)
                            if let c = l.cotacao {
                                let r = carteira.resumo(l)
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(dinheiro(r.patrimonio, r.moeda))
                                    if r.custo > 0 {
                                        TextoResultado(resultado: r.aberto, moeda: r.moeda).font(.caption)
                                    }
                                }
                                .frame(minWidth: 110, alignment: .trailing)
                                Pilula(fracao: c.variacao)
                            } else if carteira.faltaCambio(l) {
                                Text(tr("sem câmbio", "no exchange rate")).foregroundStyle(.secondary)
                            }
                        }
                        .monospacedDigit()
                    }
                }
                if !carteira.linhasBinance.isEmpty {
                    Section {
                        // Em ordem alfabética: a lista de saldos muda de ordem com as cotações e o campo pularia.
                        ForEach(carteira.linhasBinance.map(\.ativo.simbolo).sorted(), id: \.self) { CampoPrecoMedio(moeda: $0) }
                    } header: {
                        Text(tr("Preço médio de compra (em reais)", "Average purchase price (in reais)"))
                    } footer: {
                        Text(tr("Quanto você pagou, em média, por unidade de cada moeda. Com ele, o saldo entra no resultado em aberto; em branco, conta só no patrimônio.",
                                "What you paid on average per unit of each coin. With it, the balance counts toward unrealized return; left blank, only toward portfolio value."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Binance")
        .toolbar {
            ToolbarItem {
                Button { Task { await carteira.atualizar() } } label: { Label(tr("Atualizar", "Refresh"), systemImage: "arrow.clockwise") }
                    .help(tr("Atualizar saldos e cotações agora", "Refresh balances and quotes now"))
            }
        }
    }

    private func conectar() async {
        conectando = true
        erro = nil
        do {
            try await carteira.conectarBinance(chave: chave, segredo: segredo)
            chave = ""
            segredo = ""
        } catch {
            erro = error
        }
        conectando = false
    }
}

// Preço médio de uma moeda da Binance. Salva ao apertar Return ou sair do campo, não a cada tecla.
private struct CampoPrecoMedio: View {
    @Environment(Carteira.self) private var carteira
    let moeda: String
    @State private var texto = ""
    @FocusState private var focado: Bool

    private var idioma: Idioma { Ajustes.atual.idioma }
    private var invalido: Bool { !texto.isEmpty && (numero(texto, idioma: idioma) ?? 0) <= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(moeda, text: $texto, prompt: Text(tr("Não informado", "Not set")))
                .focused($focado)
                .onSubmit(salvar)
                .onChange(of: focado) { if !focado { salvar() } }
            if invalido {
                Text(tr("Use um número maior que zero, como 350000 ou 1,25.", "Use a number greater than zero, like 350000 or 1.25."))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        // Sem separador de milhar: em português numero() leria "350.000" como 350.
        .task(id: idioma) {
            texto = carteira.precoMedioBinance[moeda]?
                .formatted(FloatingPointFormatStyle<Double>(locale: idioma.locale).grouping(.never).precision(.fractionLength(0...8))) ?? ""
        }
    }

    private func salvar() {
        guard !invalido else { return }
        let preco = numero(texto, idioma: idioma)
        if preco != carteira.precoMedioBinance[moeda] { carteira.definirPrecoMedio(preco, para: moeda) }
    }
}

struct FormAdicionar: View {
    @Environment(Carteira.self) private var carteira
    @Environment(\.dismiss) private var dismiss
    let fixo: Ativo?

    @State private var venda: Bool
    @State private var cripto = false
    @State private var simbolo = ""
    @State private var quantidade = ""
    @State private var preco = ""
    @State private var data = Date.now

    // Venda só de ativo que já está na carteira.
    init(fixo: Ativo?, venda: Bool = false) {
        self.fixo = fixo
        _venda = State(initialValue: fixo != nil && venda)
    }

    private var ehCripto: Bool { fixo?.cripto ?? cripto }
    private var codigo: String { fixo?.simbolo ?? Ativo.normalizar(simbolo, cripto: cripto) }

    // Como está agora na carteira: outra folha pode ter mudado as operações depois que esta abriu.
    private var atual: Ativo {
        let novo = Ativo(simbolo: codigo, cripto: ehCripto)
        return carteira.ativos.first { $0.id == novo.id } ?? novo
    }

    private var operacao: Operacao? {
        let idioma = Ajustes.atual.idioma
        guard let q = numero(quantidade, idioma: idioma), let p = numero(preco, idioma: idioma), q > 0, p > 0 else { return nil }
        return Operacao(quantidade: q, preco: p, data: data)
    }

    // Pela quantidade digitada, mesmo antes do preço: o aviso de saldo aparece logo.
    private var problema: Problema? {
        atual.problema(venda: venda, quantidade: numero(quantidade, idioma: Ajustes.atual.idioma) ?? 0, data: data)
    }

    private var semCompra: Bool { quantidade.isEmpty && preco.isEmpty }

    // Ativo novo pode entrar sem compra (só acompanha); "Registrar" exige a operação.
    private var valido: Bool {
        !codigo.isEmpty && ((fixo == nil && semCompra) || (operacao != nil && problema == nil))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let fixo {
                    LabeledContent(tr("Ativo", "Asset"), value: fixo.simbolo)
                    Picker(tr("Operação", "Transaction"), selection: $venda) {
                        Text(tr("Compra", "Purchase")).tag(false)
                        Text(tr("Venda", "Sale")).tag(true)
                    }
                    .pickerStyle(.segmented)
                } else {
                    Picker(tr("Tipo", "Type"), selection: $cripto) {
                        Text(tr("Ação", "Stock")).tag(false)
                        Text(tr("Cripto", "Crypto")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    TextField(tr("Código", "Symbol"), text: $simbolo, prompt: Text(cripto ? "BTC, ETH, SOL" : "PETR4, VALE3, AAPL"))
                }
                Section {
                    // Exemplos no formato do idioma, que é o que numero(_:idioma:) entende.
                    TextField(tr("Quantidade", "Quantity"), text: $quantidade, prompt: Text(ehCripto ? tr("0,05", "0.05") : "100"))
                    if case .semSaldo(let disponivel) = problema {
                        let dia = quando(data, data: .abbreviated)
                        Text(disponivel > 0 ? tr("Disponível para vender em \(dia): \(qtd(disponivel)).", "Available to sell on \(dia): \(qtd(disponivel)).")
                             : tr("Não há \(codigo) para vender em \(dia).", "No \(codigo) to sell on \(dia)."))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    TextField(tr("Preço por unidade", "Price per unit"), text: $preco, prompt: Text(tr("32,50", "32.50")))
                    if !semCompra && operacao == nil {
                        Text(tr("Preencha quantidade e preço com números maiores que zero.",
                                "Enter quantity and price as numbers greater than zero, with a period for decimals (32.50)."))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    DatePicker(tr("Data", "Date"), selection: $data, in: ...Date.now, displayedComponents: .date)
                    if problema == .dataFutura {
                        Text(tr("A data não pode estar no futuro.", "The date can't be in the future."))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(venda ? tr("Venda", "Sale") : fixo == nil ? tr("Compra (opcional)", "Purchase (optional)") : tr("Compra", "Purchase"))
                } footer: {
                    let moedas = tr("Preço em reais para B3 e cripto, em dólares para ações dos EUA.",
                                    "Price in reais for B3 and crypto, in dollars for US stocks.")
                    let texto = venda ? tr("O lucro realizado é o preço de venda menos o preço médio na data. ", "Realized gain is the sale price minus the average cost on that date. ")
                        : fixo == nil ? tr("Deixe em branco para só acompanhar a cotação. ", "Leave blank to just follow the price. ") : ""
                    Text(texto + moedas)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(tr("Cancelar", "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(fixo == nil ? tr("Adicionar", "Add") : tr("Registrar", "Record")) {
                    if venda, let fixo, let operacao {
                        carteira.vender(operacao, de: fixo)
                    } else {
                        carteira.adicionar(simbolo: codigo, cripto: ehCripto, compra: operacao)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valido)
            }
            .padding()
        }
        .frame(width: 400)
    }
}

struct AjustesTela: View {
    var body: some View {
        @Bindable var ajustes = Ajustes.atual
        Form {
            Section {
                Picker(tr("Idioma", "Language"), selection: $ajustes.idioma) {
                    ForEach(Idioma.allCases) { Text($0.nome).tag($0) }
                }
                Picker(tr("Moeda", "Currency"), selection: $ajustes.moeda) {
                    ForEach(Moeda.allCases) { m in
                        Text("\(ajustes.idioma.locale.localizedString(forCurrencyCode: m.rawValue) ?? m.rawValue) (\(m.rawValue))").tag(m)
                    }
                }
            } footer: {
                Text(tr("O preço de cada ativo fica na moeda dele (PETR4 em R$, AAPL em US$; cripto em R$, ou em US$ com o dólar escolhido). Valor das posições, resultado e totais aparecem na moeda escolhida, pelo câmbio do Yahoo Finance (ou da AwesomeAPI, se o Yahoo falhar). Os menus do sistema mudam de idioma na próxima vez que o app abrir.",
                        "Each asset's price stays in its own currency (PETR4 in R$, AAPL in US$; crypto in R$, or in US$ when dollars are chosen). Position value, return and totals are shown in the chosen currency, using Yahoo Finance exchange rates (or AwesomeAPI when Yahoo fails). System menus switch language the next time the app opens."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tr("Ajustes", "Settings"))
    }
}

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
    @State private var comprando: Ativo?
    @State private var vendoCompras: Ativo?
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
                Button { vendoCompras = selecionado } label: { Label(tr("Compras", "Purchases"), systemImage: "list.bullet.rectangle") }
                    .help(tr("Ver compras do ativo selecionado (ou dê dois cliques na linha)",
                             "See the selected asset's purchases (or double-click the row)"))
                    .disabled(selecionado == nil)
            }
        }
        .sheet(isPresented: $adicionando) { FormAdicionar(fixo: nil).environment(carteira) }
        .sheet(item: $comprando) { FormAdicionar(fixo: $0).environment(carteira) }
        .sheet(item: $vendoCompras) { ComprasFolha(id: $0.id).environment(carteira) }
        .confirmationDialog(tr("Remover \(removendo?.simbolo ?? "")?", "Remove \(removendo?.simbolo ?? "")?"),
                            isPresented: .init(get: { removendo != nil }, set: { if !$0 { removendo = nil } }),
                            presenting: removendo) { ativo in
            Button(tr("Remover", "Remove"), role: .destructive) { carteira.remover(ativo) }
        } message: { ativo in
            Text(tr("O histórico de \(ativo.compras.count) compra(s) será apagado.",
                    "The history of \(ativo.compras.count) purchase(s) will be deleted."))
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
            // Preço médio e cotação na moeda do ativo; valor e resultado na moeda escolhida.
            TableColumn(tr("Preço médio", "Avg. Price")) { l in
                Text(l.quantidade > 0 ? dinheiro((l.custo ?? 0) / l.quantidade, l.moeda) : "—")
            }
            .width(min: 80, ideal: 100)
            .alignment(.trailing)
            TableColumn(tr("Cotação", "Price")) { l in
                if let c = l.cotacao {
                    Text(dinheiro(c.preco, c.moeda))
                } else {
                    Text(carteira.falhas.contains(l.ativo.id) ? tr("sem cotação", "no quote") : "…").foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 110)
            .alignment(.trailing)
            TableColumn(tr("Dia", "Day")) { l in
                if let c = l.cotacao { Pilula(fracao: c.variacao) }
            }
            .width(min: 70, ideal: 80)
            .alignment(.trailing)
            TableColumn(tr("Valor", "Value")) { l in
                if let c = l.cotacao, l.quantidade > 0 {
                    let valor = carteira.convertido(l.quantidade * c.preco, de: c.moeda)
                    Text(dinheiro(valor.valor, valor.moeda))
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 110)
            .alignment(.trailing)
            TableColumn(tr("Resultado", "Return")) { l in
                if let lucro = carteira.lucro(l) {
                    TextoResultado(resultado: lucro.resultado, moeda: lucro.moeda)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 110, ideal: 150)
            .alignment(.trailing)
        }
        .monospacedDigit()
        .contextMenu(forSelectionType: Ativo.ID.self) { ids in
            if let ativo = carteira.ativos.first(where: { $0.id == ids.first }) {
                Button(tr("Ver compras…", "View Purchases…")) { vendoCompras = ativo }
                Button(tr("Registrar compra…", "Record Purchase…")) { comprando = ativo }
                Divider()
                Button(tr("Remover \(ativo.simbolo)", "Remove \(ativo.simbolo)"), role: .destructive) {
                    if ativo.compras.isEmpty { carteira.remover(ativo) } else { removendo = ativo }
                }
            }
        } primaryAction: { ids in
            vendoCompras = carteira.ativos.first { $0.id == ids.first }
        }
    }
}

struct ComprasFolha: View {
    @Environment(Carteira.self) private var carteira
    @Environment(\.dismiss) private var dismiss
    let id: Ativo.ID
    @State private var registrando = false

    var body: some View {
        // Lê da carteira a cada mudança: apagar ou registrar atualiza a lista na hora.
        let ativo = carteira.ativos.first { $0.id == id }
        let moeda = carteira.cotacoes[id]?.moeda ?? ativo?.moedaPrevista ?? "BRL"
        let compras = ativo?.compras.sorted { $0.data > $1.data } ?? []
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let ativo { Monograma(ativo: ativo, tamanho: 30) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(ativo?.simbolo ?? "").font(.title3.weight(.semibold))
                    Text(tr("Compras registradas", "Recorded purchases")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 8)

            List(compras) { compra in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(quando(compra.data, data: .abbreviated))
                        Text("\(qtd(compra.quantidade)) × \(dinheiro(compra.preco, moeda))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(dinheiro(compra.quantidade * compra.preco, moeda)).monospacedDigit()
                    Button { if let ativo { carteira.remover(compra, de: ativo) } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help(tr("Apagar esta compra", "Delete this purchase"))
                        .accessibilityLabel(tr("Apagar compra de \(quando(compra.data, data: .numeric))",
                                               "Delete purchase from \(quando(compra.data, data: .numeric))"))
                }
                .padding(.vertical, 2)
            }
            .overlay {
                if compras.isEmpty {
                    ContentUnavailableView(tr("Sem compras", "No Purchases"), systemImage: "cart",
                                           description: Text(tr("Registre uma compra para ver o lucro ou prejuízo.",
                                                                "Record a purchase to see your gain or loss.")))
                }
            }

            HStack {
                Button(tr("Fechar", "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button { registrando = true } label: { Label(tr("Registrar compra", "Record Purchase"), systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(ativo == nil)
            }
            .padding(20)
        }
        .frame(width: 460, height: 420)
        .sheet(isPresented: $registrando) {
            if let ativo { FormAdicionar(fixo: ativo).environment(carteira) }
        }
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
                        Text(carteira.atualizadoEm == nil ? tr("Carregando…", "Loading…")
                             : tr("Nenhum saldo acima de \(dinheiro(1, "BRL")).", "No balances above \(dinheiro(1, "BRL"))."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(carteira.linhasBinance) { l in
                        HStack(spacing: 10) {
                            Monograma(ativo: l.ativo, tamanho: 22)
                            Text(l.ativo.simbolo).fontWeight(.semibold)
                            Spacer()
                            Text(qtd(l.quantidade)).foregroundStyle(.secondary)
                            if let c = l.cotacao {
                                let valor = carteira.convertido(l.quantidade * c.preco, de: c.moeda)
                                Text(dinheiro(valor.valor, valor.moeda)).frame(minWidth: 110, alignment: .trailing)
                                Pilula(fracao: c.variacao)
                            }
                        }
                        .monospacedDigit()
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

struct FormAdicionar: View {
    @Environment(Carteira.self) private var carteira
    @Environment(\.dismiss) private var dismiss
    let fixo: Ativo?

    @State private var cripto = false
    @State private var simbolo = ""
    @State private var quantidade = ""
    @State private var preco = ""
    @State private var data = Date.now

    private var ehCripto: Bool { fixo?.cripto ?? cripto }
    private var codigo: String { fixo?.simbolo ?? Ativo.normalizar(simbolo, cripto: cripto) }

    private var compra: Compra? {
        let idioma = Ajustes.atual.idioma
        guard let q = numero(quantidade, idioma: idioma), let p = numero(preco, idioma: idioma), q > 0, p > 0 else { return nil }
        return Compra(quantidade: q, preco: p, data: data)
    }

    private var semCompra: Bool { quantidade.isEmpty && preco.isEmpty }

    // Ativo novo pode entrar sem compra (só acompanha); "Registrar compra" exige a compra.
    private var valido: Bool { !codigo.isEmpty && (compra != nil || (fixo == nil && semCompra)) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let fixo {
                    LabeledContent(tr("Ativo", "Asset"), value: fixo.simbolo)
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
                    TextField(tr("Preço por unidade", "Price per unit"), text: $preco, prompt: Text(tr("32,50", "32.50")))
                    DatePicker(tr("Data", "Date"), selection: $data, in: ...Date.now, displayedComponents: .date)
                    if !semCompra && compra == nil {
                        Text(tr("Preencha quantidade e preço com números maiores que zero.",
                                "Enter quantity and price as numbers greater than zero, with a period for decimals (32.50)."))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(fixo == nil ? tr("Compra (opcional)", "Purchase (optional)") : tr("Compra", "Purchase"))
                } footer: {
                    let moedas = tr("Preço em reais para B3 e cripto, em dólares para ações dos EUA.",
                                    "Price in reais for B3 and crypto, in dollars for US stocks.")
                    Text(fixo == nil ? tr("Deixe em branco para só acompanhar a cotação. ", "Leave blank to just follow the price. ") + moedas : moedas)
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
                    carteira.adicionar(simbolo: codigo, cripto: ehCripto, compra: compra)
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
                Text(tr("O preço de cada ativo fica na moeda dele (PETR4 em R$, AAPL em US$). Valor das posições, resultado e totais aparecem na moeda escolhida, pelo câmbio do Yahoo Finance. Os menus do sistema mudam de idioma na próxima vez que o app abrir.",
                        "Each asset's price stays in its own currency (PETR4 in R$, AAPL in US$). Position value, return and totals are shown in the chosen currency, using Yahoo Finance exchange rates. System menus switch language the next time the app opens."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tr("Ajustes", "Settings"))
    }
}

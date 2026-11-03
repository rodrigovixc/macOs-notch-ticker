import SwiftUI

struct PainelView: View {
    enum Secao: String, CaseIterable, Identifiable {
        case carteira = "Carteira"
        case binance = "Binance"
        var id: Self { self }
        var icone: String { self == .carteira ? "briefcase" : "link" }
    }

    @State private var secao: Secao? = .carteira

    var body: some View {
        NavigationSplitView {
            List(Secao.allCases, selection: $secao) { s in
                Label(s.rawValue, systemImage: s.icone).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) {
                Button { NSApp.terminate(nil) } label: {
                    Label("Sair do StockNotch", systemImage: "power")
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
            }
        }
        .frame(minWidth: 880, minHeight: 480)
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
                    Label("Nenhum ativo", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("Adicione ações da B3, dos EUA ou criptomoedas para acompanhar no notch.")
                } actions: {
                    Button("Adicionar ativo") { adicionando = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                tabela
            }
        }
        .navigationTitle("Carteira")
        .toolbar {
            ToolbarItem {
                Button { adicionando = true } label: { Label("Adicionar ativo", systemImage: "plus") }
                    .help("Adicionar ação ou cripto")
            }
            ToolbarItem {
                Button { vendoCompras = selecionado } label: { Label("Compras", systemImage: "list.bullet.rectangle") }
                    .help("Ver compras do ativo selecionado (ou dê dois cliques na linha)")
                    .disabled(selecionado == nil)
            }
        }
        .sheet(isPresented: $adicionando) { FormAdicionar(fixo: nil).environment(carteira) }
        .sheet(item: $comprando) { FormAdicionar(fixo: $0).environment(carteira) }
        .sheet(item: $vendoCompras) { ComprasFolha(id: $0.id).environment(carteira) }
        .confirmationDialog("Remover \(removendo?.simbolo ?? "")?",
                            isPresented: .init(get: { removendo != nil }, set: { if !$0 { removendo = nil } }),
                            presenting: removendo) { ativo in
            Button("Remover", role: .destructive) { carteira.remover(ativo) }
        } message: { ativo in
            Text("O histórico de \(ativo.compras.count) compra(s) será apagado.")
        }
    }

    private var tabela: some View {
        Table(carteira.linhas, selection: $selecao) {
            TableColumn("Ativo") { l in
                HStack(spacing: 8) {
                    Monograma(ativo: l.ativo, tamanho: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(l.ativo.simbolo).fontWeight(.semibold)
                        Text(l.ativo.cripto ? "Cripto" : "Ação").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .width(min: 100, ideal: 120)
            TableColumn("Quantidade") { l in
                Text(l.quantidade > 0 ? qtd(l.quantidade) : "—")
            }
            .width(min: 60, ideal: 70)
            .alignment(.trailing)
            TableColumn("Preço médio") { l in
                Text(l.quantidade > 0 ? dinheiro((l.custo ?? 0) / l.quantidade, l.cotacao?.moeda ?? "BRL") : "—")
            }
            .width(min: 80, ideal: 100)
            .alignment(.trailing)
            TableColumn("Cotação") { l in
                if let c = l.cotacao {
                    Text(dinheiro(c.preco, c.moeda))
                } else {
                    Text(carteira.falhas.contains(l.ativo.id) ? "sem cotação" : "…").foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 110)
            .alignment(.trailing)
            TableColumn("Dia") { l in
                if let c = l.cotacao { Pilula(fracao: c.variacao) }
            }
            .width(min: 70, ideal: 80)
            .alignment(.trailing)
            TableColumn("Resultado") { l in
                if let c = l.cotacao, let custo = l.custo, l.quantidade > 0 {
                    TextoResultado(resultado: resultado(custo: custo, valor: l.quantidade * c.preco), moeda: c.moeda)
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
                Button("Ver compras…") { vendoCompras = ativo }
                Button("Registrar compra…") { comprando = ativo }
                Divider()
                Button("Remover \(ativo.simbolo)", role: .destructive) {
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
        let moeda = carteira.cotacoes[id]?.moeda ?? "BRL"
        let compras = ativo?.compras.sorted { $0.data > $1.data } ?? []
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let ativo { Monograma(ativo: ativo, tamanho: 30) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(ativo?.simbolo ?? "").font(.title3.weight(.semibold))
                    Text("Compras registradas").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 8)

            List(compras) { compra in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(compra.data.formatted(date: .abbreviated, time: .omitted))
                        Text("\(qtd(compra.quantidade)) × \(dinheiro(compra.preco, moeda))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(dinheiro(compra.quantidade * compra.preco, moeda)).monospacedDigit()
                    Button { if let ativo { carteira.remover(compra, de: ativo) } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Apagar esta compra")
                        .accessibilityLabel("Apagar compra de \(compra.data.formatted(date: .numeric, time: .omitted))")
                }
                .padding(.vertical, 2)
            }
            .overlay {
                if compras.isEmpty {
                    ContentUnavailableView("Sem compras", systemImage: "cart",
                                           description: Text("Registre uma compra para ver o lucro ou prejuízo."))
                }
            }

            HStack {
                Button("Fechar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button { registrando = true } label: { Label("Registrar compra", systemImage: "plus") }
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
    @State private var erro: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    if carteira.binanceConectada {
                        Label("Conectada", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Não conectada", systemImage: "circle.dashed").foregroundStyle(.secondary)
                    }
                }
                if carteira.binanceConectada {
                    Button("Desconectar", role: .destructive) { carteira.desconectarBinance() }
                } else {
                    TextField("API Key", text: $chave, prompt: Text("Cole a API Key"))
                    SecureField("Secret Key", text: $segredo, prompt: Text("Cole a Secret Key"))
                    HStack {
                        Spacer()
                        if conectando { ProgressView().controlSize(.small) }
                        Button("Conectar") { Task { await conectar() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(chave.isEmpty || segredo.isEmpty || conectando)
                    }
                }
                if let aviso = erro ?? carteira.erroBinance {
                    Label(aviso, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            } header: {
                Text("Conta")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Na Binance, crie uma chave de API deixando marcado só “Ativar leitura”. O app recusa chaves que podem negociar, transferir ou sacar, e guarda a Secret Key nas Chaves do macOS (Keychain).")
                    Link("Abrir o gerenciamento de API da Binance",
                         destination: URL(string: "https://www.binance.com/pt-BR/my/settings/api-management")!)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if carteira.binanceConectada {
                Section("Saldos (spot e Simple Earn flexível)") {
                    if carteira.linhasBinance.isEmpty {
                        Text(carteira.atualizadoEm == nil ? "Carregando…" : "Nenhum saldo acima de R$ 1.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(carteira.linhasBinance) { l in
                        HStack(spacing: 10) {
                            Monograma(ativo: l.ativo, tamanho: 22)
                            Text(l.ativo.simbolo).fontWeight(.semibold)
                            Spacer()
                            Text(qtd(l.quantidade)).foregroundStyle(.secondary)
                            if let c = l.cotacao {
                                Text(dinheiro(l.quantidade * c.preco, c.moeda)).frame(minWidth: 110, alignment: .trailing)
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
                Button { Task { await carteira.atualizar() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                    .help("Atualizar saldos e cotações agora")
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
            erro = error.localizedDescription
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
        guard let q = numero(quantidade), let p = numero(preco), q > 0, p > 0 else { return nil }
        return Compra(quantidade: q, preco: p, data: data)
    }

    private var semCompra: Bool { quantidade.isEmpty && preco.isEmpty }

    // Ativo novo pode entrar sem compra (só acompanha); "Registrar compra" exige a compra.
    private var valido: Bool { !codigo.isEmpty && (compra != nil || (fixo == nil && semCompra)) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let fixo {
                    LabeledContent("Ativo", value: fixo.simbolo)
                } else {
                    Picker("Tipo", selection: $cripto) {
                        Text("Ação").tag(false)
                        Text("Cripto").tag(true)
                    }
                    .pickerStyle(.segmented)
                    TextField("Código", text: $simbolo, prompt: Text(cripto ? "BTC, ETH, SOL" : "PETR4, VALE3, AAPL"))
                }
                Section {
                    TextField("Quantidade", text: $quantidade, prompt: Text(ehCripto ? "0,05" : "100"))
                    TextField("Preço por unidade", text: $preco, prompt: Text("32,50"))
                    DatePicker("Data", selection: $data, in: ...Date.now, displayedComponents: .date)
                    if !semCompra && compra == nil {
                        Text("Preencha quantidade e preço com números maiores que zero.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(fixo == nil ? "Compra (opcional)" : "Compra")
                } footer: {
                    Text(fixo == nil ? "Deixe em branco para só acompanhar a cotação. Preço em reais para B3 e cripto, em dólares para ações dos EUA."
                                     : "Preço em reais para B3 e cripto, em dólares para ações dos EUA.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(fixo == nil ? "Adicionar" : "Registrar") {
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

import ServiceManagement
import SwiftUI
import UserNotifications

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
        .frame(minWidth: 1080, minHeight: 480)
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
    @State private var vendoAlertas: Ativo?
    @State private var removendo: Ativo?

    private var selecionado: Ativo? { carteira.ativos.first { $0.id == selecao } }

    var body: some View {
        let semGravar = carteira.erroArquivo != nil
        Group {
            if let erro = carteira.erroArquivo, carteira.ativos.isEmpty {
                // Arquivo ilegível abre a carteira vazia: dizer "Nenhum ativo" faria parecer que as operações sumiram.
                ContentUnavailableView {
                    Label(tr("A carteira não está sendo salva", "Your portfolio isn't being saved"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(mensagem(erro))
                } actions: {
                    Button(tr("Mostrar no Finder", "Show in Finder")) { mostrarNoFinder(carteira.arquivo) }
                }
            } else if carteira.ativos.isEmpty {
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if let erro = carteira.erroArquivo, !carteira.ativos.isEmpty {
                Faixa {
                    Label(mensagem(erro), systemImage: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                    Spacer()
                    Button(tr("Mostrar no Finder", "Show in Finder")) { mostrarNoFinder(carteira.arquivo) }
                }
            }
        }
        // O mesmo aviso do notch: sem câmbio, valor e resultado de cada linha ficam na moeda do ativo.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !carteira.ativos.isEmpty, let aviso = carteira.avisoTotal {
                Faixa {
                    Label(aviso + tr(" Enquanto isso, valor e resultado ficam na moeda de cada ativo.",
                                     " Meanwhile, value and return stay in each asset's currency."),
                          systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                    Spacer()
                }
            }
        }
        .navigationTitle(tr("Carteira", "Portfolio"))
        .toolbar {
            ToolbarItem {
                Button { adicionando = true } label: { Label(tr("Adicionar ativo", "Add Asset"), systemImage: "plus") }
                    .help(tr("Adicionar ação ou cripto", "Add a stock or crypto"))
                    .disabled(semGravar)
            }
            ToolbarItem {
                Button { vendoOperacoes = selecionado } label: { Label(tr("Operações", "Transactions"), systemImage: "list.bullet.rectangle") }
                    .help(tr("Ver compras e vendas do ativo selecionado (ou dê dois cliques na linha)",
                             "See the selected asset's purchases and sales (or double-click the row)"))
                    .disabled(selecionado == nil)
            }
            ToolbarItem {
                Button { vendoAlertas = selecionado } label: { Label(tr("Alertas", "Alerts"), systemImage: "bell") }
                    .help(tr("Alertas de preço do ativo selecionado", "Price alerts for the selected asset"))
                    .disabled(selecionado == nil)
            }
        }
        .sheet(isPresented: $adicionando) { FormAdicionar(fixo: nil).environment(carteira) }
        .sheet(item: $registrando) { FormAdicionar(fixo: $0.ativo, venda: $0.venda).environment(carteira) }
        .sheet(item: $vendoOperacoes) { OperacoesFolha(id: $0.id).environment(carteira) }
        .sheet(item: $vendoAlertas) { AlertasFolha(id: $0.id).environment(carteira) }
        .confirmationDialog(tr("Remover \(removendo?.simbolo ?? "")?", "Remove \(removendo?.simbolo ?? "")?"),
                            isPresented: .init(get: { removendo != nil }, set: { if !$0 { removendo = nil } }),
                            presenting: removendo) { ativo in
            Button(tr("Remover", "Remove"), role: .destructive) { carteira.remover(ativo) }
        } message: { ativo in
            let n = ativo.compras.count + ativo.vendas.count
            let m = ativo.alertas.count
            Text(tr("\(n) operação(ões) e \(m) alerta(s) serão apagados.", "\(n) transaction(s) and \(m) alert(s) will be deleted."))
        }
    }

    private var tabela: some View {
        Table(carteira.linhas, selection: $selecao) {
            TableColumn(tr("Ativo", "Asset")) { l in
                HStack(spacing: 8) {
                    Monograma(ativo: l.ativo, tamanho: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            Text(l.ativo.simbolo).fontWeight(.semibold)
                            if !l.ativo.alertas.isEmpty {
                                let n = l.ativo.alertas.count
                                Image(systemName: "bell.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .help(tr("\(n) alerta(s) de preço", "\(n) price alert(s)"))
                                    .accessibilityLabel(tr("\(n) alerta(s) de preço", "\(n) price alert(s)"))
                            }
                        }
                        Text(l.ativo.cripto ? tr("Cripto", "Crypto") : tr("Ação", "Stock")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .width(min: 90, ideal: 110)
            TableColumn(tr("Quantidade", "Quantity")) { l in
                Text(valor: l.quantidade > 0 ? qtd(l.quantidade) : "—")
            }
            .width(min: 60, ideal: 80)
            .alignment(.trailing)
            // Preço médio na moeda das compras e cotação na do ativo; valor e resultado na moeda escolhida.
            TableColumn(tr("Preço médio", "Avg. Price")) { l in
                Text(valor: l.quantidade > 0 ? dinheiro((l.custo ?? 0) / l.quantidade, l.moedaCusto) : "—")
            }
            .width(min: 85, ideal: 100)
            .alignment(.trailing)
            TableColumn(tr("Cotação", "Price")) { l in
                if let c = l.cotacao {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(dinheiro(c.preco, c.moeda, oculto: false))
                        SeloCotacao(cotacao: c, agora: carteira.agora).font(.caption).foregroundStyle(.secondary)
                    }
                } else if carteira.falhas.contains(l.ativo.id) {
                    Text(tr("sem cotação", "no quote")).foregroundStyle(.secondary)
                } else {
                    Text(carteira.faltaCambio(l) ? tr("sem câmbio", "no exchange rate") : "…").foregroundStyle(.secondary)
                }
            }
            .width(min: 90, ideal: 110)
            .alignment(.trailing)
            TableColumn(tr("Gráfico", "Chart")) { l in
                if let c = l.cotacao { MiniGrafico(pontos: carteira.serie(l), cotacao: c) }
            }
            .width(64)
            TableColumn(tr("Dia", "Day")) { l in
                if let c = l.cotacao { Pilula(fracao: c.variacao) }
            }
            .width(min: 70, ideal: 80)
            .alignment(.trailing)
            // Valor, em aberto e realizado pela mesma conta do total do notch (resumo → somar).
            TableColumn(tr("Valor", "Value")) { l in
                let r = carteira.resumo(l)
                if l.cotacao != nil, l.quantidade > 0 {
                    Text(valor: dinheiro(r.patrimonio, r.moeda))
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 90, ideal: 110)
            .alignment(.trailing)
            // Percentual embaixo, como o selo da cotação: lado a lado não cabe na largura padrão da janela.
            TableColumn(tr("Em aberto", "Unrealized")) { l in
                let r = carteira.resumo(l)
                if r.custo > 0 {
                    VStack(alignment: .trailing, spacing: 0) {
                        TextoResultado(resultado: r.aberto, moeda: r.moeda, comPercentual: false)
                        Text(pct(r.aberto.percentual)).font(.caption).foregroundStyle(cor(r.aberto.lucro))
                    }
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 90, ideal: 110)
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
        // Coluna estreita: o número encolhe um pouco em vez de virar "…".
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .contextMenu(forSelectionType: Ativo.ID.self) { ids in
            if let ativo = carteira.ativos.first(where: { $0.id == ids.first }) {
                let semGravar = carteira.erroArquivo != nil
                Button(tr("Ver operações…", "View Transactions…")) { vendoOperacoes = ativo }
                Button(tr("Registrar compra…", "Record Purchase…")) { registrando = Registro(ativo: ativo, venda: false) }
                    .disabled(semGravar)
                Button(tr("Registrar venda…", "Record Sale…")) { registrando = Registro(ativo: ativo, venda: true) }
                    .disabled(ativo.posicao.quantidade <= 0 || semGravar)
                Button(tr("Alertas de preço…", "Price Alerts…")) { vendoAlertas = ativo }
                Divider()
                Button(tr("Remover \(ativo.simbolo)", "Remove \(ativo.simbolo)"), role: .destructive) {
                    let vazio = ativo.compras.isEmpty && ativo.vendas.isEmpty && ativo.alertas.isEmpty
                    if vazio { carteira.remover(ativo) } else { removendo = ativo }
                }
            }
        } primaryAction: { ids in
            vendoOperacoes = carteira.ativos.first { $0.id == ids.first }
        }
    }
}

// Faixa de aviso no topo ou no rodapé de uma tela, com o fundo da barra de ferramentas.
private struct Faixa<Conteudo: View>: View {
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        HStack { conteudo }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
    }
}

// O carteira.json, ou a pasta dele quando ele não existe (a gravação falhou antes de criá-lo).
@MainActor func mostrarNoFinder(_ arquivo: URL) {
    let existe = FileManager.default.fileExists(atPath: arquivo.path)
    NSWorkspace.shared.activateFileViewerSelecting([existe ? arquivo : arquivo.deletingLastPathComponent()])
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
                    Text(valor: qtd(l.operacao.quantidade))
                }
                .alignment(.trailing)
                TableColumn(tr("Preço", "Price")) { l in
                    Text(valor: dinheiro(l.operacao.preco, moeda))
                }
                .alignment(.trailing)
                TableColumn("Total") { l in
                    Text(valor: dinheiro(l.operacao.quantidade * l.operacao.preco, moeda))
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
                    .disabled((ativo?.posicao.quantidade ?? 0) <= 0 || carteira.erroArquivo != nil)
                Button { if let ativo { registrando = Registro(ativo: ativo, venda: false) } } label: {
                    Label(tr("Registrar compra", "Record Purchase"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(ativo == nil || carteira.erroArquivo != nil)
            }
            .padding(20)
        }
        .frame(width: 640, height: 440)
        .sheet(item: $registrando) { FormAdicionar(fixo: $0.ativo, venda: $0.venda).environment(carteira) }
    }
}

// Alertas de preço de um ativo: os que existem, um novo e se o macOS deixa notificar.
struct AlertasFolha: View {
    @Environment(Carteira.self) private var carteira
    @Environment(\.dismiss) private var dismiss
    let id: Ativo.ID
    @State private var tipo = Alerta.Tipo.acima
    @State private var texto = ""
    @State private var autorizacao = UNAuthorizationStatus.notDetermined

    private var idioma: Idioma { Ajustes.atual.idioma }

    var body: some View {
        // Lê da carteira a cada mudança: disparar, criar ou apagar atualiza a lista na hora.
        let ativo = carteira.ativos.first { $0.id == id }
        let cotacao = ativo.flatMap { carteira.cotacao($0) }
        // A moeda do preço como a tabela mostra; fica gravada no alerta.
        let moeda = carteira.linhas.first { $0.ativo.id == id }?.moeda ?? ativo?.moedaPrevista ?? "BRL"
        let novo = valorDigitado.map { Alerta(tipo: tipo, valor: $0, moeda: moeda) }
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let ativo { Monograma(ativo: ativo, tamanho: 30) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(ativo?.simbolo ?? "").font(.title3.weight(.semibold))
                    Text(tr("Alertas de preço", "Price alerts")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let cotacao {
                    Text(dinheiro(cotacao.preco, cotacao.moeda, oculto: false)).monospacedDigit()
                    Pilula(fracao: cotacao.variacao)
                }
            }
            .padding([.horizontal, .top], 20)

            Form {
                Section(tr("Novo alerta", "New Alert")) {
                    Picker(tr("Avisar quando", "Notify when"), selection: $tipo) {
                        Text(tr("Preço acima de", "Price above")).tag(Alerta.Tipo.acima)
                        Text(tr("Preço abaixo de", "Price below")).tag(Alerta.Tipo.abaixo)
                        Text(tr("Variação do dia de ±", "Daily change of ±")).tag(Alerta.Tipo.variacao)
                    }
                    // Exemplo no formato do idioma, que é o que numero(_:idioma:) entende.
                    let exemplo = tipo == .variacao ? tr("2,5", "2.5") : tr("55,20", "55.20")
                    TextField(tipo == .variacao ? tr("Variação (%)", "Change (%)") : tr("Preço (\(moeda))", "Price (\(moeda))"), text: $texto,
                              prompt: Text(exemplo))
                        .onSubmit { if cotacao != nil && carteira.erroArquivo == nil { adicionar(novo, a: ativo) } }
                    if !texto.isEmpty && novo == nil {
                        Text(tr("Use um número maior que zero, como \(exemplo).", "Use a number greater than zero with a period for decimals, like \(exemplo)."))
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if cotacao == nil {
                        // A moeda do alerta é a da cotação: antes dela, SAP.DE ficaria em US$ e nunca conferiria.
                        Text(tr("Aguardando a primeira cotação para saber a moeda do ativo.", "Waiting for the first quote to know the asset's currency."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let novo, let cotacao, cotacao.moeda == moeda, novo.distancia(cotacao) >= 0 {
                        Text(tr("A cotação já chegou lá: o aviso vem assim que você adicionar.", "The price is already there: you'll be notified as soon as you add it."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Spacer()
                        Button(tr("Adicionar alerta", "Add Alert")) { adicionar(novo, a: ativo) }
                            .disabled(novo == nil || ativo == nil || cotacao == nil || carteira.erroArquivo != nil)
                    }
                }

                Section {
                    if ativo?.alertas.isEmpty ?? true {
                        Text(tr("Nenhum alerta.", "No alerts.")).foregroundStyle(.secondary)
                    }
                    ForEach(ativo?.alertas ?? []) { alerta in
                        HStack(spacing: 8) {
                            Image(systemName: alerta.tipo == .acima ? "arrow.up.right" : alerta.tipo == .abaixo ? "arrow.down.right" : "plusminus")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(alerta.descricao).monospacedDigit()
                                // Ação tem uma moeda só: alerta em outra (criado antes da cotação, numa versão antiga) não confere.
                                if let cotacao, ativo?.cripto == false, alerta.moeda != cotacao.moeda {
                                    Text(tr("A cotação é em \(cotacao.moeda): este alerta nunca dispara. Apague e crie de novo.",
                                            "The price is in \(cotacao.moeda): this alert never fires. Delete it and add it again."))
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            if alerta.disparado {
                                Label(tr("Atingido", "Triggered"), systemImage: "bell.badge")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .help(tr("Já avisou; avisa de novo depois que a cotação voltar para o outro lado.",
                                             "Already notified; notifies again after the price moves back to the other side."))
                            }
                            Button { if let ativo { carteira.remover(alerta, de: ativo) } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help(tr("Apagar este alerta", "Delete this alert"))
                                .accessibilityLabel(tr("Apagar alerta: \(alerta.descricao)", "Delete alert: \(alerta.descricao)"))
                        }
                    }
                } header: {
                    Text(tr("Alertas", "Alerts"))
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        aviso
                        Text(tr("Avisa uma vez quando a cotação cruza o valor, e de novo só depois que ela voltar para o outro lado. O preço é na moeda do ativo, como na tabela.",
                                "Notifies once when the price crosses the value, and again only after it moves back to the other side. The price is in the asset's currency, as in the table."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(tr("Fechar", "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 480, height: 520)
        .task { autorizacao = await Notificacoes.autorizacao() }
        // Volta de Ajustes do Sistema com as notificações ligadas: o aviso some.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { autorizacao = await Notificacoes.autorizacao() }
        }
    }

    private var valorDigitado: Double? {
        guard let v = numero(texto, idioma: idioma), v > 0 else { return nil }
        return tipo == .variacao ? v / 100 : v
    }

    // Sem permissão (ou fora do .app) o alerta continua contando, mas o aviso não aparece: melhor dizer.
    @ViewBuilder private var aviso: some View {
        if !emPacote {
            Label(tr("Notificações só funcionam no StockNotch.app (monte com ./build.sh).", "Notifications only work in StockNotch.app (build it with ./build.sh)."),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if autorizacao == .denied {
            HStack {
                Label(tr("As notificações do StockNotch estão desligadas.", "StockNotch notifications are turned off."), systemImage: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
                if let url = Notificacoes.ajustesDoSistema {
                    Button(tr("Abrir Ajustes do Sistema…", "Open System Settings…")) { NSWorkspace.shared.open(url) }
                        .controlSize(.small)
                }
            }
        }
    }

    // Limpa o campo antes de esperar a permissão: dois cliques não criam dois alertas.
    private func adicionar(_ alerta: Alerta?, a ativo: Ativo?) {
        guard let alerta, let ativo else { return }
        texto = ""
        Task {
            await carteira.adicionar(alerta, a: ativo)
            autorizacao = await Notificacoes.autorizacao()
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
                        let poeira = carteira.moeda == "USD" ? "USD" : "BRL"  // a moeda da cotação de cripto (ver linhasDeSaldo)
                        Text(carteira.atualizadoEm == nil ? tr("Carregando…", "Loading…")
                             : tr("Nenhum saldo acima de \(dinheiro(1, poeira, oculto: false)).", "No balances above \(dinheiro(1, poeira, oculto: false))."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(carteira.linhasBinance) { l in
                        HStack(spacing: 10) {
                            Monograma(ativo: l.ativo, tamanho: 22)
                            Text(l.ativo.simbolo).fontWeight(.semibold)
                            Spacer()
                            Text(valor: qtd(l.quantidade)).foregroundStyle(.secondary)
                            if let c = l.cotacao {
                                let r = carteira.resumo(l)
                                // Como no notch e na tabela da Carteira: a idade do dado e o desenho do dia junto do valor.
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(valor: dinheiro(r.patrimonio, r.moeda))
                                    if r.custo > 0 {
                                        TextoResultado(resultado: r.aberto, moeda: r.moeda).font(.caption)
                                    }
                                    SeloCotacao(cotacao: c, agora: carteira.agora).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(minWidth: 110, alignment: .trailing)
                                MiniGrafico(pontos: carteira.serie(l), cotacao: c)
                                Pilula(fracao: c.variacao)
                            } else if carteira.falhas.contains(l.ativo.id) {
                                Text(tr("sem cotação", "no quote")).foregroundStyle(.secondary)
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
        Group {
            if Ajustes.atual.privacidade {
                // O campo mostraria o número: no modo privacidade fica só a leitura, oculta.
                LabeledContent(moeda) { Text(valor: carteira.precoMedioBinance[moeda].map { dinheiro($0, "BRL") } ?? tr("Não informado", "Not set")) }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    TextField(moeda, text: $texto, prompt: Text(tr("Não informado", "Not set")))
                        .focused($focado)
                        .disabled(carteira.erroArquivo != nil)  // não seria salvo
                        .onSubmit(salvar)
                        .onChange(of: focado) { if !focado { salvar() } }
                    if invalido {
                        Text(tr("Use um número maior que zero, como 350.000 ou 1,25.", "Use a number greater than zero, like 350,000 or 1.25."))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .onDisappear(perform: salvar)  // ligar o modo privacidade (ou trocar de aba) no meio da edição não a perde
            }
        }
        // Sem separador de milhar: o número volta ao campo como se costuma digitar (numero() aceita os dois).
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
                        Text(valor: disponivel > 0 ? tr("Disponível para vender em \(dia): \(qtd(disponivel)).", "Available to sell on \(dia): \(qtd(disponivel)).")
                             : tr("Não há \(codigo) para vender em \(dia).", "No \(codigo) to sell on \(dia)."))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    TextField(tr("Preço por unidade", "Price per unit"), text: $preco, prompt: Text(tr("32,50", "32.50")))
                    if !semCompra && operacao == nil {
                        Text(tr("Preencha quantidade e preço com números maiores que zero, como 1.234,50.",
                                "Enter quantity and price as numbers greater than zero, like 1,234.50."))
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let operacao {
                        // O total denuncia o separador trocado ("1.500" BTC é mil e quinhentos, não um e meio).
                        // Sem ocultar: os dois números já estão visíveis nos campos.
                        Text("Total: " + dinheiro(operacao.quantidade * operacao.preco, atual.moedaPrevista, oculto: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
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
                .disabled(!valido || carteira.erroArquivo != nil)  // não seria salvo: o painel mostra o porquê
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
            Section {
                Toggle(tr("Modo privacidade", "Privacy mode"), isOn: $ajustes.privacidade)
            } footer: {
                Text(tr("Esconde valores e quantidades no notch e no painel (R$ ••••). Cotações e percentuais continuam visíveis. Também no menu do notch (clique com o botão direito).",
                        "Hides amounts and quantities in the notch and in this window (R$ ••••). Prices and percentages stay visible. Also in the notch menu (right-click)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            SecaoAbrirComMac()
        }
        .formStyle(.grouped)
        .navigationTitle(tr("Ajustes", "Settings"))
    }
}

// Abrir com o Mac pelo SMAppService. O status vem sempre do sistema: o usuário também liga e desliga
// em Ajustes do Sistema, e o registro pode ficar esperando a aprovação dele.
private struct SecaoAbrirComMac: View {
    @State private var status = SMAppService.Status.notRegistered
    @State private var erro: Falha?

    var body: some View {
        Section {
            Toggle(tr("Abrir com o Mac", "Open at login"), isOn: Binding(get: { status == .enabled || status == .requiresApproval }, set: { alternar($0) }))
                .disabled(!emPacote)
            if status == .requiresApproval {
                HStack {
                    Label(tr("Falta aprovar em Ajustes do Sistema > Geral > Itens de Início.", "Needs approval in System Settings > General > Login Items."),
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button(tr("Abrir Itens de Início…", "Open Login Items…")) { SMAppService.openSystemSettingsLoginItems() }
                }
            } else if status == .notFound {
                Label(tr("O macOS não encontrou o app. Mova o StockNotch.app para Aplicativos e tente de novo.",
                         "macOS couldn't find the app. Move StockNotch.app to Applications and try again."),
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if let erro {
                Label(mensagem(erro), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        } footer: {
            Text(emPacote ? tr("Também dá para mudar em Ajustes do Sistema > Geral > Itens de Início.",
                               "You can also change this in System Settings > General > Login Items.")
                 : tr("Disponível só no StockNotch.app (monte com ./build.sh): rodando com swift run, não há app para o macOS abrir.",
                      "Only available in StockNotch.app (build it with ./build.sh): when run with swift run, there's no app for macOS to open."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: ler)
        // Volta de Ajustes do Sistema, onde o usuário pode ter aprovado ou desligado.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in ler() }
    }

    // Esperando aprovação, o aviso laranja já explica e leva aos Itens de Início: o erro do register() seria repetido.
    private func ler() {
        if emPacote { status = SMAppService.mainApp.status }
        if status == .requiresApproval { erro = nil }
    }

    private func alternar(_ ligar: Bool) {
        erro = nil
        do {
            if ligar { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // Só o código: o texto do sistema viria no idioma em que o app abriu. O comum (1, sem permissão) ganha texto.
            let codigo = (error as NSError).code
            erro = codigo == Int(EPERM) || codigo == kSMErrorLaunchDeniedByUser
                ? Falha("O macOS não deixou: libere o StockNotch em Ajustes do Sistema > Geral > Itens de Início.",
                        "macOS didn't allow it: allow StockNotch in System Settings > General > Login Items.")
                : Falha("Não consegui mudar a abertura com o Mac (erro \(codigo)).", "Couldn't change opening at login (error \(codigo)).")
        }
        ler()
    }
}

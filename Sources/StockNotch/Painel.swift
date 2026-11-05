import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct PainelView: View {
    enum Secao: CaseIterable, Identifiable {
        case visao, carteira, binance, noticias, widget, ajustes
        var id: Self { self }

        var icone: String {
            switch self {
            case .visao: "chart.pie"
            case .carteira: "briefcase"
            case .binance: "link"
            case .noticias: "newspaper"
            case .widget: "menubar.rectangle"
            case .ajustes: "gearshape"
            }
        }

        @MainActor var nome: String {
            switch self {
            case .visao: tr("Visão geral", "Overview")
            case .carteira: tr("Carteira", "Portfolio")
            case .binance: "Binance"
            case .noticias: tr("Notícias", "News")
            case .widget: "Widget"
            case .ajustes: tr("Ajustes", "Settings")
            }
        }
    }

    @State private var secao: Secao? = .visao

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
            switch secao ?? .visao {
            case .visao: VisaoGeralTela()
            case .carteira: CarteiraTela()
            case .binance: BinanceTela()
            case .noticias:
                ScrollView { ColunaNoticias(limite: 60, escuro: false).padding(24).frame(maxWidth: 760, alignment: .leading) }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .navigationTitle(tr("Notícias", "News"))
            case .widget: WidgetTela()
            case .ajustes: AjustesTela()
            }
        }
        .frame(minWidth: 1080, minHeight: 480)
        // Vidro: a área de trabalho aparece desfocada atrás da janela, e a barra lateral flutua por cima (macOS 26+).
        // Design system do tema: fundo, cor de destaque, tipografia e aparência clara ou escura.
        .background { FundoDoPainel().ignoresSafeArea() }
        .tint(Ajustes.atual.tema.estilo.destaque)
        // nil no padrão: um fontDesign(.default) por cima anularia a serifa que o Luxo põe nos títulos.
        .fontDesign(Ajustes.atual.tema.estilo.fonte == .default ? nil : Ajustes.atual.tema.estilo.fonte)
        .preferredColorScheme(Ajustes.atual.tema.estilo.esquema)
        // Controles nativos (DatePicker etc.) seguem o idioma do app, não o do sistema.
        .environment(\.locale, Ajustes.atual.idioma.locale)
    }
}

struct CarteiraTela: View {
    @Environment(Carteira.self) private var carteira
    @State private var selecao: Ativo.ID?
    @State private var adicionando = false
    @State private var importando = false
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
            } else if carteira.ativos.isEmpty && carteira.linhasBinance.isEmpty {
                ContentUnavailableView {
                    Label(tr("Nenhum ativo", "No assets"), systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text(tr("Adicione ações da B3, dos EUA ou criptomoedas para acompanhar no notch.",
                            "Add B3 or US stocks or crypto to follow them in the notch."))
                } actions: {
                    Button(tr("Adicionar ativo", "Add Asset")) { adicionando = true }
                        .buttonStyle(.borderedProminent)
                    Button(tr("Importar…", "Import…")) { importando = true }
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
                Button { importando = true } label: { Label(tr("Importar…", "Import…"), systemImage: "square.and.arrow.down") }
                    .help(tr("Importar compras e vendas de um CSV", "Import purchases and sales from a CSV"))
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
        .sheet(isPresented: $importando) { ImportarFolha().environment(carteira) }
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
        // Comprados, saldos da Binance e a lista de desejos, nessa ordem (como no notch). Linha da Binance não tem
        // operações nem alertas no app: o menu e os botões da barra de ferramentas ficam sem efeito nela.
        let linhas = carteira.linhas.filter { !$0.desejo } + carteira.linhasBinance + carteira.linhas.filter(\.desejo)
        return Table(linhas, selection: $selecao) {
            TableColumn(tr("Ativo", "Asset")) { l in
                CelulaAtivo(carteira: carteira, linha: l) { HStack(spacing: 8) {
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
                        HStack(spacing: 4) {
                            // Da Binance é sempre cripto: a etiqueta diz de onde vem, e o círculo do monograma, o tipo.
                            if l.binance { Etiqueta.binance } else { Etiqueta.tipo(l.ativo.cripto) }
                            if l.desejo { Etiqueta.desejo }
                        }
                    }
                }
                .padding(.vertical, 2) }
            }
            .width(min: 90, ideal: 110)
            TableColumn(tr("Quantidade", "Quantity")) { l in
                Text(valor: l.quantidade > 0 ? qtd(l.quantidade) : "—")
            }
            .width(min: 60, ideal: 80)
            .alignment(.trailing)
            // Preço médio na moeda das compras e cotação na do ativo; valor e resultado na moeda escolhida.
            TableColumn(tr("Preço médio", "Avg. Price")) { l in
                // Saldo da Binance sem preço médio informado não tem custo: "—", não R$ 0,00.
                let medio = carteira.naMoedaDe(l, (l.custo ?? 0) / max(l.quantidade, 1e-12), de: l.moedaCusto)
                Text(valor: l.quantidade > 0 && l.custo != nil ? dinheiro(medio.valor, medio.moeda) : "—")
            }
            .width(min: 85, ideal: 100)
            .alignment(.trailing)
            TableColumn(tr("Cotação", "Price")) { l in
                if let c = l.cotacao {
                    let preco = carteira.naMoedaDe(l, c.preco, de: c.moeda)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(dinheiro(preco.valor, preco.moeda, oculto: false))
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
                let r = carteira.resumoDoAtivo(l)
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
                let r = carteira.resumoDoAtivo(l)
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
                let r = carteira.resumoDoAtivo(l)
                if r.realizado != 0 {
                    TextoResultado(resultado: Resultado(lucro: r.realizado, percentual: 0), moeda: r.moeda, comPercentual: false)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 100)
            .alignment(.trailing)
        }
        // Sem fundo nem faixas: as linhas ficam sobre o vidro da janela.
        .scrollContentBackground(.hidden)
        .alternatingRowBackgrounds(.disabled)
        .monospacedDigit()
        // Coluna estreita: o número encolhe um pouco em vez de virar "…".
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .contextMenu(forSelectionType: Ativo.ID.self) { ids in
            if let id = ids.first, let l = linhas.first(where: { $0.id == id }) { MenuMoeda(linha: l) }
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
            .scrollContentBackground(.hidden)  // os grupos ficam como cartões sobre o vidro

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
                    } else if carteira.erroChave != nil {
                        Label(tr("Chave salva, sem acesso", "Key saved, no access"), systemImage: "lock.trianglebadge.exclamationmark")
                            .foregroundStyle(.orange)
                    } else {
                        Label(tr("Não conectada", "Not connected"), systemImage: "circle.dashed").foregroundStyle(.secondary)
                    }
                }
                if carteira.binanceConectada {
                    Button(tr("Desconectar", "Disconnect"), role: .destructive) { carteira.desconectarBinance() }
                } else if let erroChave = carteira.erroChave {
                    // A chave não sumiu: pedir para colar de novo seria o caminho errado.
                    Label(mensagem(erroChave), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    HStack {
                        Button(tr("Desconectar", "Disconnect"), role: .destructive) { carteira.desconectarBinance() }
                        Spacer()
                        Button(tr("Tentar de novo", "Try Again")) {
                            carteira.lerChave()
                            Task { await carteira.atualizar() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
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
                                let r = carteira.resumoDoAtivo(l)
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
                        .contextMenu { MenuMoeda(linha: l) }
                    }
                }
                if carteira.linhasBinance.contains(where: { ($0.custo ?? 0) > 0 }) {
                    Section(tr("Lucro ou prejuízo por moeda", "Gain or loss by coin")) { PagoContraHoje() }
                }
                if !carteira.criptoContraPrecoMedio.isEmpty {
                    Section {
                        CriptoContraPrecoMedio()
                    } header: {
                        Text(tr("Preço contra o preço médio", "Price vs. average cost"))
                    } footer: {
                        Text(tr("Quanto cada moeda está acima ou abaixo do que você pagou em média, dia a dia. A linha tracejada (0%) é o preço médio. Clique na legenda para escolher as moedas (até 8).",
                                "How far each coin is above or below what you paid on average, day by day. The dashed line (0%) is the average cost. Click the legend to choose coins (up to 8)."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !carteira.linhasBinance.isEmpty {
                    Section {
                        // Em ordem alfabética: a lista de saldos muda de ordem com as cotações e o campo pularia.
                        ForEach(carteira.linhasBinance.map(\.ativo.simbolo).sorted(), id: \.self) { CampoPrecoMedio(moeda: $0) }
                    } header: {
                        Text(tr("Preço médio de compra (em reais)", "Average purchase price (in reais)"))
                    } footer: {
                        Text(tr("Calculado pelas suas ordens no Spot e pelo Converter da Binance. Digite um valor para usar o seu no lugar (moeda que veio de depósito não aparece nas trocas); em branco, vale o calculado.",
                                "Calculated from your Binance Spot orders and Convert history. Type a value to use yours instead (coins deposited from elsewhere don't show up in trades); left blank, the calculated one applies."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)  // os grupos ficam como cartões sobre o vidro
        .navigationTitle("Binance")
        .task { await carteira.carregarHistorico() }
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
                LabeledContent(moeda) { Text(valor: carteira.precoMedio[moeda].map { dinheiro($0, "BRL") } ?? tr("Não informado", "Not set")) }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    TextField(moeda, text: $texto, prompt: Text(carteira.precoMedioAuto[moeda]
                        .map { tr("Da Binance: ", "From Binance: ") + dinheiro($0, "BRL") } ?? tr("Não informado", "Not set")))
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
    @State private var desejo = false
    @State private var sugestoes: [Sugestao] = []
    @State private var escolhida: Sugestao?

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

    // Na lista de desejos o ativo entra sem compra; comprado (e "Registrar") exige a operação.
    private var valido: Bool {
        !codigo.isEmpty && ((fixo == nil && desejo) || (operacao != nil && problema == nil))
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
                    Picker(tr("Entra como", "Add as"), selection: $desejo) {
                        Label(tr("Comprado", "Owned"), systemImage: "bag.fill").tag(false)
                        Label(tr("Lista de desejos", "Wishlist"), systemImage: "star.fill").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Picker(tr("Tipo", "Type"), selection: $cripto) {
                        Text(tr("Ação", "Stock")).tag(false)
                        Text(tr("Cripto", "Crypto")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    TextField(tr("Buscar", "Search"), text: $simbolo,
                              prompt: Text(tr("Nome ou código: Petrobras, PETR4, Bitcoin", "Name or symbol: Apple, AAPL, Bitcoin")))
                    if let escolhida, escolhida.simbolo == simbolo {
                        Text(escolhida.nome).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(sugestoes) { s in
                        Button { escolher(s) } label: { LinhaSugestao(sugestao: s) }
                            .buttonStyle(.plain)
                    }
                }
                if fixo != nil || !desejo {
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
                    Text(venda ? tr("Venda", "Sale") : tr("Compra", "Purchase"))
                } footer: {
                    let moedas = tr("Preço em reais para B3 e cripto, em dólares para ações dos EUA.",
                                    "Price in reais for B3 and crypto, in dollars for US stocks.")
                    let texto = venda ? tr("O lucro realizado é o preço de venda menos o preço médio na data. ", "Realized gain is the sale price minus the average cost on that date. ") : ""
                    Text(texto + moedas)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                } else {
                    Text(tr("Na lista de desejos o ativo só é acompanhado: aparece no notch e no letreiro, com cotação, gráfico e alertas, mas não entra no patrimônio. Ao registrar uma compra, ele passa a contar.",
                            "On the wishlist the asset is only followed: it shows in the notch and the ticker, with price, chart and alerts, but doesn't count toward your portfolio value. Record a purchase and it starts counting."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)  // os grupos ficam como cartões sobre o vidro
            // Busca enquanto digita, com uma pausa para não pedir a cada letra. Escolher uma sugestão encerra a busca.
            .task(id: simbolo) {
                guard fixo == nil, simbolo.count >= 2, simbolo != escolhida?.simbolo else { return sugestoes = [] }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let achadas = try? await buscarAtivos(simbolo) else { return }
                // Em português, ou com o Mac na região Brasil (inglês em en-BR), a B3 vem primeiro: "petro" acha PETR4
                // antes das Petroleum americanas.
                let brasil = Ajustes.atual.idioma == .pt || Locale.current.region?.identifier == "BR"
                let b3 = brasil ? achadas.filter { $0.bolsa == "São Paulo" } : []
                sugestoes = Array((b3 + achadas.filter { !b3.contains($0) }).prefix(8))
            }
            HStack {
                Spacer()
                Button(tr("Cancelar", "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(fixo != nil ? tr("Registrar", "Record") : desejo ? tr("Adicionar à lista", "Add to Wishlist") : tr("Adicionar", "Add")) {
                    if venda, let fixo, let operacao {
                        carteira.vender(operacao, de: fixo)
                    } else {
                        carteira.adicionar(simbolo: codigo, cripto: ehCripto, compra: fixo == nil && desejo ? nil : operacao)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valido || carteira.erroArquivo != nil)  // não seria salvo: o painel mostra o porquê
            }
            .padding()
        }
        .frame(width: 440)
    }

    private func escolher(_ s: Sugestao) {
        escolhida = s
        cripto = s.cripto
        simbolo = s.simbolo
        sugestoes = []
    }
}

private struct LinhaSugestao: View {
    let sugestao: Sugestao

    var body: some View {
        HStack(spacing: 8) {
            Monograma(ativo: Ativo(simbolo: sugestao.simbolo, cripto: sugestao.cripto), tamanho: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(sugestao.simbolo).fontWeight(.semibold)
                Text(sugestao.nome).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(sugestao.bolsa).font(.caption).foregroundStyle(.tertiary)
            Etiqueta.tipo(sugestao.cripto)
        }
        .contentShape(Rectangle())
    }
}

// Na tabela, parar o mouse numa ação abre os mesmos indicadores do notch num balão ao lado.
// A carteira vem por parâmetro: as células da Table não recebem o .environment(carteira) e o app cairia.
private struct CelulaAtivo<Conteudo: View>: View {
    let carteira: Carteira
    let linha: Linha
    @ViewBuilder let conteudo: Conteudo
    @State private var mouse = false
    @State private var balao = false

    var body: some View {
        conteudo
            .contentShape(Rectangle())
            .onHover { mouse = $0 && !linha.ativo.cripto }
            .task(id: mouse) {
                // A espera evita abrir um balão em cada linha por onde o mouse só passa.
                try? await Task.sleep(for: .milliseconds(mouse ? 500 : 250))
                guard !Task.isCancelled else { return }
                balao = mouse
                if mouse { await carteira.carregarIndicadores(linha.ativo) }
            }
            .popover(isPresented: $balao, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(linha.ativo.simbolo).font(.headline)
                    DetalheAcao(indicadores: carteira.indicadores[linha.ativo.id], moeda: linha.moeda)
                }
                .padding(14)
                .frame(width: 460)
            }
    }
}

// Fundo de janela translúcido, desfocando o que está atrás dela.
struct FundoDeVidro: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let vidro = NSVisualEffectView()
        vidro.material = .underWindowBackground
        vidro.blendingMode = .behindWindow
        vidro.state = .followsWindowActiveState
        return vidro
    }

    func updateNSView(_ vidro: NSVisualEffectView, context: Context) {}
}

// Ação ou cripto, comprado ou lista de desejos: cor e ícone além do texto.
struct Etiqueta: View {
    let texto: String
    let icone: String
    let cor: Color

    var body: some View {
        Label(texto, systemImage: icone)
            .font(.system(size: 9.5, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .foregroundStyle(cor)
            .background(cor.opacity(0.15), in: Capsule())
            .fixedSize()
    }

    @MainActor static func tipo(_ cripto: Bool) -> Etiqueta {
        cripto ? Etiqueta(texto: tr("Cripto", "Crypto"), icone: "bitcoinsign.circle.fill", cor: .orange)
            : Etiqueta(texto: tr("Ação", "Stock"), icone: "building.columns.fill", cor: .blue)
    }

    @MainActor static var binance: Etiqueta { Etiqueta(texto: "Binance", icone: "link", cor: .yellow) }

    @MainActor static var desejo: Etiqueta { Etiqueta(texto: tr("Desejo", "Wishlist"), icone: "star.fill", cor: .yellow) }
}

// Colar ou abrir um CSV (formato em Importar.swift), conferir linha a linha e gravar tudo de uma vez.
// Linha com erro trava o botão: importar só as boas e corrigir depois duplicaria essas na segunda vez.
struct ImportarFolha: View {
    @Environment(Carteira.self) private var carteira
    @Environment(\.dismiss) private var dismiss
    @State private var texto = ""
    @State private var escolhendo = false

    var body: some View {
        let linhas = lerCSV(texto, ativos: carteira.ativos)
        let validas = linhas.compactMap { try? $0.resultado.get() }
        let erros = linhas.count - validas.count
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Importar operações", "Import Transactions")).font(.headline)
            Text(tr("Uma operação por linha: tipo (compra ou venda), ativo, cripto (sim ou nao), quantidade, preço e data. Ponto nos decimais, sem separador de milhar, e data ano-mês-dia. Preço em reais para B3 e cripto, em dólares para ações dos EUA.",
                    "One transaction per line: type (buy or sell), symbol, crypto (yes or no), quantity, price and date. Decimal point, no thousands separator, and year-month-day dates. Price in reais for B3 and crypto, in dollars for US stocks."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $texto)
                .font(.system(.callout, design: .monospaced))
                .overlay(alignment: .topLeading) {
                    if texto.isEmpty {
                        Text(tr("compra,PETR4,nao,200,38.40,2026-03-10\nvenda,PETR4,nao,50,47.10,2026-09-02\ncompra,BTC,sim,0.015,385000,2026-06-01",
                                "buy,AAPL,no,10,231.50,2026-05-20\nsell,AAPL,no,4,250,2026-09-02\nbuy,BTC,yes,0.015,385000,2026-06-01"))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
            List(linhas) { LinhaImportacao(linha: $0) }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
            HStack {
                Button(tr("Abrir arquivo…", "Open File…")) { escolhendo = true }
                Spacer()
                if erros > 0 {
                    Text(tr("\(erros) linha(s) com erro", "\(erros) line(s) with errors")).foregroundStyle(.red)
                } else if !validas.isEmpty {
                    Text(tr("\(validas.count) operação(ões)", "\(validas.count) transaction(s)")).foregroundStyle(.secondary)
                }
                Button(tr("Cancelar", "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                // false: a carteira mudou enquanto a folha estava aberta; a lista refaz a conta e mostra o porquê.
                Button(tr("Importar", "Import")) { if carteira.importar(validas) { dismiss() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(validas.isEmpty || erros > 0 || carteira.erroArquivo != nil)
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
        .fileImporter(isPresented: $escolhendo, allowedContentTypes: [.commaSeparatedText, .plainText]) { resultado in
            guard case .success(let url) = resultado else { return }
            let acesso = url.startAccessingSecurityScopedResource()
            defer { if acesso { url.stopAccessingSecurityScopedResource() } }
            // Vai para o editor: dá para corrigir uma linha antes de importar. Planilha antiga do Excel sai em Latin-1.
            if let lido = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) {
                texto = lido
            }
        }
    }
}

private struct LinhaImportacao: View {
    let linha: LinhaCSV

    var body: some View {
        HStack(spacing: 10) {
            Text("\(linha.numero)")
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .trailing)
            switch linha.resultado {
            case .success(let i):
                let moeda = i.ativo.moedaPrevista
                // Sem ocultar no modo privacidade: são os números que a pessoa acabou de digitar ou abrir.
                Text(i.venda ? tr("Venda", "Sale") : tr("Compra", "Purchase"))
                    .foregroundStyle(i.venda ? .orange : .secondary)
                    .frame(width: 64, alignment: .leading)
                Text(i.ativo.simbolo).fontWeight(.semibold)
                Text(quando(i.operacao.data, data: .abbreviated)).foregroundStyle(.secondary)
                Spacer()
                Text("\(qtd(i.operacao.quantidade, oculto: false)) × \(dinheiro(i.operacao.preco, moeda, oculto: false))")
                    .foregroundStyle(.secondary)
                Text(dinheiro(i.operacao.quantidade * i.operacao.preco, moeda, oculto: false))
                    .frame(minWidth: 110, alignment: .trailing)
            case .failure(let falha):
                Label(mensagem(falha), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .help(linha.resultado.failure.map { mensagem($0) } ?? "")
    }
}

private extension Result {
    var failure: Failure? { if case .failure(let f) = self { f } else { nil } }
}

// Onde o widget fica, o que ele mostra fechado e quais ativos giram no letreiro. Muda na hora, sem reabrir.
struct WidgetTela: View {
    @Environment(Carteira.self) private var carteira

    var body: some View {
        @Bindable var ajustes = Ajustes.atual
        let linhas = carteira.linhas + carteira.linhasBinance
        let girando = linhas.filter { !ajustes.foraDoLetreiro.contains($0.id) }.count
        Form {
            Section {
                Picker(tr("Posição", "Position"), selection: $ajustes.posicao) {
                    Text(tr("No notch, no topo da tela", "In the notch, at the top of the screen")).tag(PosicaoWidget.notch)
                    Text(tr("Solto, onde você arrastar", "Floating, wherever you drag it")).tag(PosicaoWidget.livre)
                }
                .pickerStyle(.radioGroup)
                if #available(macOS 26.0, *) {
                    Toggle(tr("Vidro (Liquid Glass)", "Glass (Liquid Glass)"), isOn: $ajustes.vidro)
                }
                if ajustes.posicao == .livre {
                    Button(tr("Voltar para o topo da tela", "Move Back to the Top of the Screen")) { ajustes.ancoraLivre = nil }
                        .disabled(ajustes.ancoraLivre == nil)
                }
            } footer: {
                nota(tr("Solto, arraste o widget com o mouse para qualquer lugar, em qualquer tela. Ele lembra onde ficou. O vidro vale solto e em telas sem notch; no notch de verdade o widget fica preto, para se fundir com ele.",
                        "When floating, drag the widget anywhere, on any display. It remembers where you left it. Glass applies when floating and on displays without a notch; in a real notch the widget stays black to blend in."))
            }
            Section {
                Toggle(tr("Coluna de últimas notícias", "Latest news column"), isOn: $ajustes.noticias)
            } header: {
                Text(tr("Aberto", "Expanded"))
            } footer: {
                nota(tr("Ao passar o mouse, o widget mostra ao lado da carteira as notícias dos últimos 2 dias sobre os seus ativos (Google Notícias, de 10 em 10 minutos). Clique numa para abrir no navegador. Também ficam na aba Notícias.",
                        "On hover, the widget shows news from the last 2 days about your assets next to your portfolio (Google News, every 10 minutes). Click one to open it in the browser. They're also in the News tab."))
            }
            Section {
                Picker(tr("Mostrar", "Show"), selection: $ajustes.estilo) {
                    Text(tr("Ativo e variação do dia (PETR4 ▲ 1,20%)", "Asset and daily change (PETR4 ▲ 1.20%)")).tag(EstiloWidget.variacao)
                    Text(tr("Ativo e cotação (PETR4 R$ 50,12)", "Asset and price (PETR4 R$50.12)")).tag(EstiloWidget.preco)
                    Text(tr("Ativo, cotação e variação", "Asset, price and change")).tag(EstiloWidget.completo)
                    Text(tr("Total da carteira e variação do dia, sem girar", "Portfolio total and daily change, no rotation")).tag(EstiloWidget.total)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text(tr("Fechado", "Collapsed"))
            } footer: {
                nota(tr("Passe o mouse no widget para ver a carteira inteira.", "Hover over the widget to see your whole portfolio."))
            }
            Section {
                Picker(tr("Ao mesmo tempo", "At a time"), selection: $ajustes.quantos) {
                    ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(tr("Dividir: metade ações, metade cripto", "Split: half stocks, half crypto"), isOn: $ajustes.dividir)
                    .disabled(ajustes.quantos < 2)
                Picker(tr("Trocar a cada", "Switch every"), selection: $ajustes.ritmo) {
                    ForEach([2, 4, 6, 10], id: \.self) { Text("\($0) s").tag($0) }
                }
                .pickerStyle(.segmented)
                if linhas.isEmpty {
                    Text(tr("Adicione ativos na Carteira ou conecte a Binance.", "Add assets in Portfolio or connect Binance."))
                        .foregroundStyle(.secondary)
                }
                ForEach(linhas) { l in
                    Toggle(isOn: Binding(get: { !Ajustes.atual.foraDoLetreiro.contains(l.id) },
                                         set: { if $0 { Ajustes.atual.foraDoLetreiro.remove(l.id) } else { Ajustes.atual.foraDoLetreiro.insert(l.id) } })) {
                        HStack(spacing: 8) {
                            Monograma(ativo: l.ativo, tamanho: 18)
                            Text(l.ativo.simbolo)
                            if l.binance { Text("Binance").foregroundStyle(.secondary) }
                        }
                    }
                }
            } header: {
                Text(tr("Letreiro", "Ticker"))
            } footer: {
                nota(linhas.isEmpty ? "" : tr("\(girando) de \(linhas.count) ativos giram no widget. Ativo novo entra girando. Dividindo, as ações ficam à esquerda e as cripto à direita, cada lado com a sua vez. Com mais de um ao mesmo tempo, o widget fica mais largo e, no notch, pode cobrir itens da barra de menus.",
                                              "\(girando) of \(linhas.count) assets rotate in the widget. New assets are included. When split, stocks go on the left and crypto on the right, each side taking its own turns. With more than one at a time the widget gets wider and, in the notch, may cover menu bar items."))
            }
            .disabled(ajustes.estilo == .total)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)  // os grupos ficam como cartões sobre o vidro
        .navigationTitle("Widget")
    }

    private func nota(_ texto: String) -> some View {
        Text(texto)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AjustesTela: View {
    var body: some View {
        @Bindable var ajustes = Ajustes.atual
        Form {
            Section {
                SeletorDeTema(ajustes: ajustes)
            } header: {
                Text(tr("Tema", "Theme"))
            } footer: {
                Text(tr("Cada tema é um design system: cores, tipografia, cantos, cartões, densidade e o layout da Visão geral (cartões, compacto ou editorial). Alta e baixa continuam verde e vermelho.",
                        "Each theme is a design system: colors, typography, corners, cards, density and the Overview layout (cards, compact or editorial). Gains and losses stay green and red."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
        .scrollContentBackground(.hidden)  // os grupos ficam como cartões sobre o vidro
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

// Em que moeda a linha do ativo aparece (preço, valor e resultado). Vale para o mesmo ativo em toda parte.
struct MenuMoeda: View {
    let linha: Linha

    var body: some View {
        let ajustes = Ajustes.atual
        Picker(tr("Mostrar em", "Show in"), selection: Binding(
            get: { ajustes.moedaDoAtivo[linha.ativo.id] ?? "" },
            set: { ajustes.moedaDoAtivo[linha.ativo.id] = $0.isEmpty ? nil : $0 }
        )) {
            Text(tr("Moeda própria (\(linha.moeda))", "Own currency (\(linha.moeda))")).tag("")
            Text(tr("Real (BRL)", "Brazilian real (BRL)")).tag("BRL")
            Text(tr("Dólar (USD)", "US dollar (USD)")).tag("USD")
            Text(tr("Euro (EUR)", "Euro (EUR)")).tag("EUR")
        }
        .pickerStyle(.menu)
        Divider()
    }
}

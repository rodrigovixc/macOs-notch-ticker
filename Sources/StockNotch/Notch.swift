import SwiftUI

// A vez do letreiro: `quantos` seguidos a partir da página `indice`, dando a volta na lista. Com até `quantos`
// ativos, todos, parados.
func pagina<T>(_ lista: [T], quantos: Int, indice: Int) -> [T] {
    guard lista.count > quantos else { return lista }
    let inicio = (indice % lista.count) * quantos % lista.count
    return (0..<quantos).map { lista[(inicio + $0) % lista.count] }
}

// Metade de cada lista, cada uma com a sua vez; o ímpar fica com a primeira. Lado com menos itens que vagas cede as
// que sobram ao outro (1 ação e 3 vagas: 1 ação e 2 cripto).
func paginaDividida<T>(_ a: [T], _ b: [T], quantos: Int, indice: Int) -> ([T], [T]) {
    let nB = min(quantos - min((quantos + 1) / 2, a.count), b.count)
    let nA = min(quantos - nB, a.count)
    return (pagina(a, quantos: nA, indice: indice), pagina(b, quantos: nB, indice: indice))
}

// Medidas do notch da tela. Em monitor sem notch a largura é 0 e vira uma pílula no topo.
struct NotchGeometria {
    var largura: CGFloat
    var altura: CGFloat

    // Solto não há notch para contornar: uma pílula só, sem o vão do meio.
    static let solta = NotchGeometria(largura: 0, altura: 26)
}

extension NotchGeometria {
    init(_ tela: NSScreen?) {
        guard let tela else {
            largura = 0
            altura = 24
            return
        }
        if let esquerda = tela.auxiliaryTopLeftArea, let direita = tela.auxiliaryTopRightArea {
            largura = tela.frame.width - esquerda.width - direita.width
        } else {
            largura = 0
        }
        altura = max(tela.safeAreaInsets.top, tela.frame.maxY - tela.visibleFrame.maxY, 24)
    }
}

@MainActor @Observable
final class EstadoNotch {
    var mouseDentro = false
}

// Janela sem borda grudada no topo da tela, por cima da barra de menus, em todas as mesas.
final class NotchPanel: NSPanel {
    private let carteira: Carteira
    private let abrirPainel: () -> Void
    private let estado = EstadoNotch()
    private var tamanho = CGSize.zero

    static var tela: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main }

    init(carteira: Carteira, abrirPainel: @escaping () -> Void) {
        self.carteira = carteira
        self.abrirPainel = abrirPainel
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        montar()
        orderFrontRegardless()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.montar() }
        }
        observar()
    }

    // Trocar entre notch e solto, ou "voltar para o topo" nos Ajustes, sem o tamanho mudar: reposiciona mesmo assim.
    private func observar() {
        withObservationTracking {
            _ = Ajustes.atual.posicao
            _ = Ajustes.atual.ancoraLivre
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.posicionar()
                self?.observar()
            }
        }
    }

    // Não rouba o teclado do app em que você está.
    override var canBecomeKey: Bool { false }

    private func montar() {
        let view = NotchView(geometria: NotchGeometria(Self.tela), estado: estado, abrirPainel: abrirPainel,
                             mouseNaJanela: { [weak self] in self?.frame.contains(NSEvent.mouseLocation) ?? false },
                             aoMudarTamanho: { [weak self] in self?.ajustar($0) },
                             arrastar: { [weak self] in self?.arrastar($0) })
        let host = HospedeiroNotch(rootView: AnyView(view.environment(carteira)))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        let area = AreaNotch()
        area.aoPassarMouse = { [estado] dentro in estado.mouseDentro = dentro }
        area.addSubview(host)
        contentView = area
        host.frame = area.bounds
    }

    // A janela tem sempre o tamanho do desenho, para não bloquear cliques no que está atrás.
    private func ajustar(_ novo: CGSize) {
        let encolhe = novo.width < tamanho.width || novo.height < tamanho.height
        tamanho = novo
        guard encolhe else { return posicionar() }
        // Espera a animação de fechar terminar antes de encolher a janela.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            posicionar()
        }
    }

    // O CGEvent conta do topo da tela principal para baixo; o AppKit, de baixo para cima.
    private static var pontoDoEvento: CGPoint? {
        guard let evento = NSApp.currentEvent?.cgEvent, let altura = NSScreen.screens.first?.frame.height else { return nil }
        return CGPoint(x: evento.location.x, y: altura - evento.location.y)
    }

    // Topo e centro do widget: o notch, ou onde ele foi solto (de início, logo abaixo da barra de menus).
    private var ancora: CGPoint {
        if Ajustes.atual.posicao == .livre {
            if let ancora = Ajustes.atual.ancoraLivre { return ancora }
            let area = (NSScreen.main ?? Self.tela)?.visibleFrame ?? .zero
            return CGPoint(x: area.midX, y: area.maxY - 8)
        }
        let tela = Self.tela?.frame ?? .zero
        return CGPoint(x: tela.midX, y: tela.maxY)
    }

    private func posicionar() {
        let livre = Ajustes.atual.posicao == .livre
        var quadro = NSRect(x: ancora.x - tamanho.width / 2, y: ancora.y - tamanho.height, width: tamanho.width, height: tamanho.height)
        // Solto não sai da tela: aberto perto da borda, desliza para dentro.
        if livre, let area = (NSScreen.screens.first { $0.frame.contains(ancora) } ?? NSScreen.main)?.visibleFrame {
            quadro.origin.x = min(max(quadro.minX, area.minX), area.maxX - quadro.width)
            quadro.origin.y = min(max(quadro.minY, area.minY), area.maxY - quadro.height)
        }
        hasShadow = livre  // no notch a sombra apareceria em volta do preto da barra de menus
        setFrame(quadro, display: true)
        invalidateShadow()
    }

    // Solto, arrastar move o widget (fechado ou aberto). A conta é na tela, pelo ponto do próprio evento: o do gesto
    // anda junto com a janela e a faria correr na frente do mouse.
    private var arrasto: (mouse: CGPoint, ancora: CGPoint)?

    private func arrastar(_ movendo: Bool) {
        guard Ajustes.atual.posicao == .livre else { return }
        guard movendo else {
            // Guarda onde ficou de fato: perto da borda, a janela foi empurrada para dentro.
            if arrasto != nil { Ajustes.atual.ancoraLivre = CGPoint(x: frame.midX, y: frame.maxY) }
            arrasto = nil
            return
        }
        let mouse = Self.pontoDoEvento ?? NSEvent.mouseLocation
        let inicio = arrasto ?? (mouse, ancora)
        arrasto = inicio
        Ajustes.atual.ancoraLivre = CGPoint(x: inicio.ancora.x + mouse.x - inicio.mouse.x, y: inicio.ancora.y + mouse.y - inicio.mouse.y)
        posicionar()
    }
}

// Rastreia o mouse mesmo com o app em segundo plano (.activeAlways).
final class AreaNotch: NSView {
    var aoPassarMouse: (Bool) -> Void = { _ in }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { aoPassarMouse(true) }
    override func mouseExited(with event: NSEvent) { aoPassarMouse(false) }
}

// O primeiro clique já aperta o botão, sem precisar ativar a janela antes.
final class HospedeiroNotch: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct NotchView: View {
    @Environment(Carteira.self) private var carteira
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento
    let geometria: NotchGeometria
    let estado: EstadoNotch
    let abrirPainel: () -> Void
    let mouseNaJanela: () -> Bool
    let aoMudarTamanho: (CGSize) -> Void
    let arrastar: (Bool) -> Void  // true enquanto move, false ao soltar

    @State private var expandido = false
    @State private var indice = 0

    private let larguraAberta: CGFloat = 480  // cabe o minigráfico ao lado do preço

    private var livre: Bool { Ajustes.atual.posicao == .livre }
    private var geo: NotchGeometria { livre ? .solta : geometria }

    // Quantos ativos o widget fechado mostra lado a lado; o total é um só.
    private var quantos: Int { Ajustes.atual.estilo == .total ? 1 : min(max(Ajustes.atual.quantos, 1), 4) }

    // Um ativo com o seu valor, quando são vários lado a lado.
    private var larguraItem: CGFloat {
        switch Ajustes.atual.estilo {
        case .variacao: 105
        case .preco: 120
        case .completo, .total: 165
        }
    }
    private let vao: CGFloat = 12  // entre dois ativos

    // Largura de cada lado do notch fechado, pelo que ele mostra (o mais largo: "R$ 428.753,68 ▲ 1,23%").
    // Vários ativos se dividem entre os dois lados; o esquerdo leva o ímpar.
    private var orelha: CGFloat {
        if quantos > 1 {
            let lado = CGFloat((quantos + 1) / 2)
            return lado * larguraItem + (lado - 1) * vao + 14
        }
        return switch Ajustes.atual.estilo {
        case .variacao: 80
        case .preco: 110
        case .total: 120
        case .completo: 170
        }
    }
    private let maximoLinhas = 10

    // Sem o vão do notch (solto, ou tela sem notch), vários ativos ficam numa fila só, sem buraco no meio.
    private var semVao: Bool { geo.largura == 0 }

    private var larguraFechada: CGFloat {
        guard semVao && quantos > 1 else { return geo.largura + 2 * orelha }
        return CGFloat(quantos) * larguraItem + CGFloat(quantos - 1) * vao + 28
    }

    private var animacao: Animation {
        reduzirMovimento ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.82)
    }

    // No notch, só os cantos de baixo (o de cima é a borda da tela); solto, os quatro, e fechado vira pílula.
    private var forma: UnevenRoundedRectangle {
        let raio: CGFloat = expandido ? 24 : livre ? geo.altura / 2 : 12
        let topo = livre ? raio : 0
        return UnevenRoundedRectangle(topLeadingRadius: topo, bottomLeadingRadius: raio, bottomTrailingRadius: raio,
                                      topTrailingRadius: topo, style: .continuous)
    }

    private var arrasto: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { _ in arrastar(true) }
            .onEnded { _ in arrastar(false) }
    }

    var body: some View {
        Group {
            if expandido {
                aberto.transition(.opacity)
            } else {
                fechado.transition(.opacity)
            }
        }
        .frame(width: expandido ? max(larguraAberta, larguraFechada) : larguraFechada, alignment: .top)
        .frame(minHeight: geo.altura, alignment: .top)
        .background(.black)
        .clipShape(forma)
        // Solto pode cair em fundo preto: um contorno leve mostra onde ele está.
        .overlay { if livre { forma.stroke(.white.opacity(0.14), lineWidth: 1) } }
        .contentShape(forma)
        .gesture(arrasto, including: livre ? .all : .subviews)
        .onTapGesture {
            if !expandido { withAnimation(animacao) { expandido = true } }
        }
        .contextMenu {
            Button(tr("Abrir painel…", "Open StockNotch…"), action: abrirPainel)
            @Bindable var ajustes = Ajustes.atual
            Toggle(tr("Modo privacidade", "Privacy Mode"), isOn: $ajustes.privacidade)
            Divider()
            Button(tr("Sair do StockNotch", "Quit StockNotch")) { NSApp.terminate(nil) }
        }
        .fixedSize()
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: aoMudarTamanho)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .task(id: estado.mouseDentro) {
            // A espera evita abrir sem querer quando o mouse só passa a caminho da barra de menus.
            try? await Task.sleep(for: .milliseconds(estado.mouseDentro ? 150 : 350))
            guard !Task.isCancelled else { return }
            withAnimation(animacao) { expandido = estado.mouseDentro }
        }
        .task(id: expandido) {
            // Rede de segurança: se o macOS não avisar que o mouse saiu (ex.: aberto por clique), fecha mesmo assim.
            // Com o VoiceOver não: quem abriu pela ação dele não tem o mouse ali, e fecha pela ação "Fechar".
            while expandido && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if expandido && !mouseNaJanela() && !NSWorkspace.shared.isVoiceOverEnabled {
                    estado.mouseDentro = false
                    withAnimation(animacao) { expandido = false }
                }
            }
        }
        .task(id: Ajustes.atual.ritmo) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Ajustes.atual.ritmo))
                guard !Task.isCancelled else { return }
                withAnimation(animacao) { indice &+= 1 }
            }
        }
    }

    // MARK: Fechado: um ativo de cada vez, nas "orelhas" ao lado do notch

    // Só o que está no letreiro (página Widget do painel) e já tem cotação.
    private var letreiro: [Linha] {
        let fora = Ajustes.atual.foraDoLetreiro
        return (carteira.linhas + carteira.linhasBinance).filter { $0.cotacao != nil && !fora.contains($0.id) }
    }

    private var destaque: Linha? { pagina(letreiro, quantos: 1, indice: indice).first }

    private var troca: AnyTransition {
        reduzirMovimento ? .opacity : .push(from: .bottom)
    }

    // Estilo da página Widget: o ativo da vez com variação, cotação ou as duas; ou o total da carteira, parado.
    private var fechado: some View {
        let estilo = Ajustes.atual.estilo
        let total = estilo == .total ? carteira.total : nil
        let atual = estilo == .total ? nil : destaque
        return Group { if quantos > 1 { varios } else { HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if let total {
                    Text(valor: dinheiro(total.patrimonio, total.moeda))
                        .contentTransition(.numericText())
                } else if let atual {
                    Text(atual.ativo.simbolo)
                        .id(atual.id)
                        .transition(troca)
                } else {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: orelha - 14, alignment: .leading)

            Spacer(minLength: geo.largura)

            ZStack(alignment: .trailing) {
                if let total {
                    variacao(total.hojePct)
                } else if let atual, let c = atual.cotacao {
                    HStack(spacing: 6) {
                        if estilo != .variacao { Text(dinheiro(c.preco, c.moeda, oculto: false)) }
                        if estilo != .preco { variacao(c.variacao) }
                    }
                    .id(atual.id)
                    .transition(troca)
                }
            }
            .frame(width: orelha - 14, alignment: .trailing)
        } } }
        .font(.system(size: 12, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 14)
        .frame(height: geo.altura)
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(atualAcessivel)
        .accessibilityHint(tr("Passe o mouse ou clique para ver a carteira", "Hover or click to see your portfolio"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { withAnimation(animacao) { expandido = true } }
        .accessibilityAction(named: tr("Abrir painel", "Open StockNotch"), abrirPainel)
    }

    // A página com vários: a metade da esquerda (o ímpar fica com ela) e a da direita. Dividindo, ações à esquerda
    // e cripto à direita, cada lado com a sua vez; faltando um dos dois tipos, divide a lista como sempre.
    private var paginaVarios: (esquerda: [Linha], direita: [Linha]) {
        let meio = (quantos + 1) / 2
        let acoes = letreiro.filter { !$0.ativo.cripto }
        let cripto = letreiro.filter(\.ativo.cripto)
        if Ajustes.atual.dividir && !acoes.isEmpty && !cripto.isEmpty {
            return paginaDividida(acoes, cripto, quantos: quantos, indice: indice)
        }
        let itens = pagina(letreiro, quantos: quantos, indice: indice)
        return (Array(itens.prefix(meio)), Array(itens.dropFirst(meio)))
    }

    // Vários de uma vez: a página do letreiro, dividida pelos dois lados do notch (sem notch, numa fila só).
    @ViewBuilder private var varios: some View {
        let (esquerda, direita) = paginaVarios
        if esquerda.isEmpty && direita.isEmpty {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        } else if semVao {
            fila(esquerda + direita)
        } else {
            HStack(spacing: 0) {
                fila(esquerda).frame(width: orelha - 14, alignment: .leading)
                Spacer(minLength: geo.largura)
                fila(direita).frame(width: orelha - 14, alignment: .trailing)
            }
        }
    }

    private func fila(_ itens: [Linha]) -> some View {
        let estilo = Ajustes.atual.estilo
        return HStack(spacing: vao) {
            ForEach(itens) { l in
                HStack(spacing: 5) {
                    Text(l.ativo.simbolo)
                    if let c = l.cotacao {
                        if estilo != .variacao { Text(dinheiro(c.preco, c.moeda, oculto: false)).foregroundStyle(.white.opacity(0.75)) }
                        if estilo != .preco { variacao(c.variacao) }
                    }
                }
                .transition(troca)
            }
        }
    }

    private func variacao(_ fracao: Double) -> some View {
        HStack(spacing: 3) {
            Seta(valor: fracao)
            Text(pct(abs(fracao), sinal: false))
        }
        .foregroundStyle(cor(fracao))
    }

    private var atualAcessivel: String {
        if Ajustes.atual.estilo == .total {
            guard let total = carteira.total else { return "StockNotch" }
            let valor = falado(dinheiro(total.patrimonio, total.moeda))
            return tr("Carteira, \(valor), \(pct(total.hojePct)) hoje", "Portfolio, \(valor), \(pct(total.hojePct)) today")
        }
        let (esquerda, direita) = paginaVarios
        let itens = (quantos > 1 ? esquerda + direita : Array(destaque.map { [$0] } ?? [])).compactMap { l in
            l.cotacao.map { c in
                let preco = Ajustes.atual.estilo == .variacao ? "" : dinheiro(c.preco, c.moeda, oculto: false) + ", "
                return tr("\(l.ativo.simbolo), \(preco)\(pct(c.variacao)) hoje", "\(l.ativo.simbolo), \(preco)\(pct(c.variacao)) today")
            }
        }
        return itens.isEmpty ? "StockNotch" : itens.joined(separator: "; ")
    }

    // MARK: Aberto: patrimônio e lista

    private var aberto: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("StockNotch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: geo.largura + 16)
                Button(action: abrirPainel) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(tr("Abrir painel", "Open StockNotch"))
                .accessibilityLabel(tr("Abrir painel", "Open StockNotch"))
            }
            .frame(height: geo.altura)

            if carteira.linhas.isEmpty && carteira.linhasBinance.isEmpty {
                vazio
            } else {
                resumo
                Divider().overlay(Color.white.opacity(0.12))
                lista
            }
            rodape
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .foregroundStyle(.white)
        .accessibilityAction(named: tr("Fechar", "Close")) {
            estado.mouseDentro = false
            withAnimation(animacao) { expandido = false }
        }
    }

    private var vazio: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Nenhum ativo ainda", "No assets yet"))
                .font(.system(size: 15, weight: .semibold))
            Text(tr("Adicione ações e criptomoedas ou conecte sua conta da Binance.", "Add stocks and crypto or connect your Binance account."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button(tr("Abrir painel", "Open StockNotch"), action: abrirPainel)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 4)
        }
    }

    // Um total só, na moeda escolhida. Sem câmbio para alguma posição, avisa em vez de somar errado.
    @ViewBuilder private var resumo: some View {
        if let total = carteira.total {
            if total.patrimonio > 0 || total.realizado != 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Patrimônio", "Portfolio value"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(valor: dinheiro(total.patrimonio, total.moeda))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    HStack(spacing: 14) {
                        Indicador(rotulo: tr("Hoje", "Today"), resultado: Resultado(lucro: total.hoje, percentual: total.hojePct), moeda: total.moeda)
                        if total.custo > 0 {
                            Indicador(rotulo: tr("Em aberto", "Unrealized"), resultado: total.aberto, moeda: total.moeda)
                        }
                    }
                    // Linha própria: três indicadores não cabem lado a lado no notch.
                    if total.realizado != 0 {
                        Indicador(rotulo: tr("Realizado", "Realized"), resultado: Resultado(lucro: total.realizado, percentual: 0),
                                  moeda: total.moeda, comPercentual: false)
                    }
                }
            }
        } else if let aviso = carteira.avisoTotal {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(aviso)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    private var lista: some View {
        let manuais = Array(carteira.linhas.prefix(maximoLinhas))
        let binance = Array(carteira.linhasBinance.prefix(maximoLinhas - manuais.count))
        let ocultos = carteira.linhas.count + carteira.linhasBinance.count - manuais.count - binance.count
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(manuais) { LinhaNotch(linha: $0, falhou: carteira.falhas.contains($0.ativo.id)) }
            if !binance.isEmpty {
                Text("BINANCE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.top, manuais.isEmpty ? 0 : 4)
                ForEach(binance) { LinhaNotch(linha: $0, falhou: carteira.falhas.contains($0.ativo.id)) }
            }
            if ocultos > 0 {
                Button(tr("Mais \(ocultos) no painel", "\(ocultos) more in StockNotch"), action: abrirPainel)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var aviso: String? {
        if let erro = carteira.erroArquivo { return mensagem(erro) }
        if let erro = carteira.erroBinance { return "Binance: \(mensagem(erro))" }
        let semCotacao = carteira.simbolosSemCotacao.joined(separator: ", ")
        if !semCotacao.isEmpty { return tr("Sem cotação: \(semCotacao)", "No quote: \(semCotacao)") }
        guard let paradas = carteira.paradas else { return nil }
        let desde = momento(paradas.desde, agora: carteira.agora)
        let lista = paradas.simbolos.joined(separator: ", ")
        return tr("Sem atualizar desde \(desde): \(lista)", "Not updated since \(desde): \(lista)")
    }

    @ViewBuilder private var rodape: some View {
        HStack(spacing: 6) {
            if let aviso {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(aviso).lineLimit(2)
            } else if let hora = carteira.atualizadoEm {
                // A idade de cada cotação fica no selo da linha (ao vivo, 15 min, fechado).
                Image(systemName: "arrow.clockwise")
                Text(tr("Atualizado às \(quando(hora, hora: .standard))", "Updated at \(quando(hora, hora: .standard))"))
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
    }
}

struct Indicador: View {
    let rotulo: String
    let resultado: Resultado
    let moeda: String
    var comPercentual = true

    var body: some View {
        HStack(spacing: 4) {
            Text(rotulo).foregroundStyle(.secondary)
            Seta(valor: resultado.lucro).foregroundStyle(cor(resultado.lucro))
            TextoResultado(resultado: resultado, moeda: moeda, comPercentual: comPercentual)
        }
        .font(.system(size: 11, weight: .medium))
        .accessibilityElement(children: .combine)
    }
}

struct LinhaNotch: View {
    @Environment(Carteira.self) private var carteira
    let linha: Linha
    let falhou: Bool
    @State private var mouse = false
    @State private var detalhe = false

    // Ação: parar o mouse na linha abre os indicadores embaixo dela (cripto não tem fundamentos).
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            principal
            if detalhe {
                DetalheAcao(indicadores: carteira.indicadores[linha.ativo.id], moeda: linha.moeda)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { mouse = $0 && !linha.ativo.cripto }
        .task(id: mouse) {
            // A espera evita abrir cada linha por onde o mouse só passa.
            try? await Task.sleep(for: .milliseconds(mouse ? 400 : 150))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { detalhe = mouse }
            if mouse { await carteira.carregarIndicadores(linha.ativo) }
        }
    }

    @ViewBuilder private var principal: some View {
        let r = carteira.resumo(linha)
        let situacao = linha.quantidade > 0 ? tr("\(qtd(linha.quantidade)) un.", "Qty \(qtd(linha.quantidade))")
            : linha.ativo.compras.isEmpty ? tr("acompanhando", "watching") : tr("posição encerrada", "position closed")
        HStack(spacing: 10) {
            Monograma(ativo: linha.ativo)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(linha.ativo.simbolo).font(.system(size: 13, weight: .semibold))
                    if let c = linha.cotacao {
                        SeloCotacao(cotacao: c, agora: carteira.agora)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(valor: situacao)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let c = linha.cotacao {
                MiniGrafico(pontos: carteira.serie(linha), cotacao: c)
                // Largura mínima de um preço de seis dígitos: os minigráficos formam coluna.
                VStack(alignment: .trailing, spacing: 1) {
                    Text(dinheiro(c.preco, c.moeda, oculto: false))
                        .font(.system(size: 13, weight: .medium))
                        .contentTransition(.numericText())
                    // Preço na moeda do ativo; resultado e valor da posição na moeda escolhida, pela conta do total.
                    // Sem o percentual, que não cabe na linha: ele fica na dica e no VoiceOver (na tabela, embaixo).
                    if r.custo > 0 {
                        let completo = "\(dinheiro(r.aberto.lucro, r.moeda, sinal: true)) (\(pct(r.aberto.percentual)))"
                        TextoResultado(resultado: r.aberto, moeda: r.moeda, comPercentual: false)
                            .font(.system(size: 11))
                            .help(completo)
                            .accessibilityLabel(falado(completo))
                    } else if linha.quantidade > 0 {
                        // Saldo da Binance sem preço médio: só o valor.
                        Text(valor: dinheiro(r.patrimonio, r.moeda))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    // Venda parcial também: o realizado aparece aqui como na tabela do painel.
                    if r.realizado != 0 {
                        HStack(spacing: 4) {
                            Text(tr("Realizado", "Realized")).foregroundStyle(.secondary)
                            TextoResultado(resultado: Resultado(lucro: r.realizado, percentual: 0), moeda: r.moeda, comPercentual: false)
                        }
                        .font(.system(size: r.custo > 0 ? 10 : 11))
                    }
                }
                .frame(minWidth: 100, alignment: .trailing)
                .monospacedDigit()
                Pilula(fracao: c.variacao)
                    .frame(width: 74, alignment: .trailing)
            } else if falhou {
                Text(tr("sem cotação", "no quote")).font(.system(size: 11)).foregroundStyle(.secondary)
            } else if carteira.faltaCambio(linha) {
                Text(tr("sem câmbio", "no exchange rate")).font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        // Uma linha por texto: sem espaço, encolhe um pouco em vez de quebrar ou virar "ao…".
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityElement(children: .combine)
    }
}

// Os principais indicadores de uma ação, em quatro colunas: o pregão de hoje, o ano e os fundamentos.
// São dados de mercado, não da carteira: o modo privacidade não esconde.
struct DetalheAcao: View {
    let indicadores: Indicadores?
    let moeda: String

    var body: some View {
        if let i = indicadores {
            let m = i.currency ?? moeda
            let preco = { (v: Double?) in v.map { dinheiro($0, m, oculto: false) } }
            let itens: [(String, String?)] = [
                (tr("Abertura", "Open"), preco(i.regularMarketOpen)),
                (tr("Máx. do dia", "Day high"), preco(i.regularMarketDayHigh)),
                (tr("Mín. do dia", "Day low"), preco(i.regularMarketDayLow)),
                (tr("Fech. anterior", "Prev. close"), preco(i.regularMarketPreviousClose)),
                (tr("Volume", "Volume"), i.regularMarketVolume.map(compacto)),
                (tr("Vol. médio 3M", "Avg. vol. 3M"), i.averageDailyVolume3Month.map(compacto)),
                (tr("Máx. 52 sem.", "52-wk high"), preco(i.fiftyTwoWeekHigh)),
                (tr("Mín. 52 sem.", "52-wk low"), preco(i.fiftyTwoWeekLow)),
                (tr("Valor de mercado", "Market cap"), i.marketCap.map { compacto($0, moeda: m) }),
                (tr("P/L", "P/E"), i.trailingPE.map(numero2)),
                (tr("LPA", "EPS"), preco(i.epsTrailingTwelveMonths)),
                (tr("Div. yield", "Div. yield"), i.dividendYield.map { pct($0 / 100, sinal: false) }),
                (tr("P/VP", "P/B"), i.priceToBook.map(numero2)),
            ]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4), alignment: .leading, spacing: 8) {
                ForEach(itens, id: \.0) { rotulo, valor in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rotulo).font(.system(size: 9.5)).foregroundStyle(.secondary)
                        Text(valor ?? "—").font(.system(size: 11, weight: .medium)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(tr("Buscando indicadores…", "Loading indicators…")).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
    }

    private func numero2(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(2)).locale(Ajustes.atual.idioma.locale))
    }

    // 19.361.000 → "19,4 mi"; com moeda, "R$ 668,4 bi".
    private func compacto(_ v: Double) -> String {
        v.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(Ajustes.atual.idioma.locale))
    }

    private func compacto(_ v: Double, moeda: String) -> String {
        v.formatted(.currency(code: moeda).notation(.compactName).precision(.fractionLength(0...1)).locale(Ajustes.atual.idioma.locale))
    }
}

extension Carteira {
    // Por que não há total, no notch e no painel com o mesmo texto. Câmbio velho não entra no total: melhor nenhum do
    // que um que mistura instantes diferentes. O app só busca o câmbio do dólar e do euro: outra moeda nunca converte.
    var avisoTotal: String? {
        guard total == nil else { return nil }
        let faltando = cambiosFaltando.isEmpty ? semCambio : cambiosFaltando
        let fora = faltando.filter { !["USD", "EUR"].contains($0) }
        if !fora.isEmpty {
            let lista = fora.joined(separator: ", ")
            return tr("Total indisponível: o app não converte \(lista) (só real, dólar e euro).",
                      "Total unavailable: StockNotch can't convert \(lista) (only BRL, USD and EUR).")
        }
        let lista = faltando.joined(separator: ", ")
        if let parado = cambioParado {
            return tr("Total indisponível: o câmbio de \(lista) não atualiza desde \(momento(parado, agora: agora)).",
                      "Total unavailable: the \(lista) exchange rate hasn't updated since \(momento(parado, agora: agora)).")
        }
        return tr("Total indisponível: falta o câmbio de \(lista).", "Total unavailable: no \(lista) exchange rate.")
    }
}

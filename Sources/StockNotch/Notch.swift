import SwiftUI

// Medidas do notch da tela. Em monitor sem notch a largura é 0 e vira uma pílula no topo.
struct NotchGeometria {
    var largura: CGFloat
    var altura: CGFloat

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
    }

    // Não rouba o teclado do app em que você está.
    override var canBecomeKey: Bool { false }

    private func montar() {
        let view = NotchView(geometria: NotchGeometria(Self.tela), estado: estado, abrirPainel: abrirPainel,
                             mouseNaJanela: { [weak self] in self?.frame.contains(NSEvent.mouseLocation) ?? false },
                             aoMudarTamanho: { [weak self] in self?.ajustar($0) })
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

    private func posicionar() {
        guard let tela = Self.tela?.frame else { return }
        setFrame(NSRect(x: tela.midX - tamanho.width / 2, y: tela.maxY - tamanho.height,
                        width: tamanho.width, height: tamanho.height), display: true)
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

    @State private var expandido = false
    @State private var indice = 0

    private let orelha: CGFloat = 80
    private let larguraAberta: CGFloat = 420
    private let maximoLinhas = 10

    private var animacao: Animation {
        reduzirMovimento ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.82)
    }

    private var forma: UnevenRoundedRectangle {
        let raio: CGFloat = expandido ? 24 : 12
        return UnevenRoundedRectangle(bottomLeadingRadius: raio, bottomTrailingRadius: raio, style: .continuous)
    }

    var body: some View {
        Group {
            if expandido {
                aberto.transition(.opacity)
            } else {
                fechado.transition(.opacity)
            }
        }
        .frame(width: expandido ? max(larguraAberta, geometria.largura + 2 * orelha) : geometria.largura + 2 * orelha, alignment: .top)
        .frame(minHeight: geometria.altura, alignment: .top)
        .background(.black)
        .clipShape(forma)
        .contentShape(forma)
        .onTapGesture {
            if !expandido { withAnimation(animacao) { expandido = true } }
        }
        .contextMenu {
            Button("Abrir painel…", action: abrirPainel)
            Divider()
            Button("Sair do StockNotch") { NSApp.terminate(nil) }
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
            while expandido && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if expandido && !mouseNaJanela() {
                    estado.mouseDentro = false
                    withAnimation(animacao) { expandido = false }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                withAnimation(animacao) { indice &+= 1 }
            }
        }
    }

    // MARK: Fechado: um ativo de cada vez, nas "orelhas" ao lado do notch

    private var destaque: Linha? {
        let lista = (carteira.linhas + carteira.linhasBinance).filter { $0.cotacao != nil }
        return lista.isEmpty ? nil : lista[indice % lista.count]
    }

    private var troca: AnyTransition {
        reduzirMovimento ? .opacity : .push(from: .bottom)
    }

    private var fechado: some View {
        let atual = destaque
        return HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if let atual {
                    Text(atual.ativo.simbolo)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .id(atual.id)
                        .transition(troca)
                } else {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: orelha - 14, alignment: .leading)

            Spacer(minLength: geometria.largura)

            ZStack(alignment: .trailing) {
                if let atual, let c = atual.cotacao {
                    HStack(spacing: 3) {
                        Seta(valor: c.variacao)
                        Text(abs(c.variacao).formatted(.percent.precision(.fractionLength(2))))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(cor(c.variacao))
                    .id(atual.id)
                    .transition(troca)
                }
            }
            .frame(width: orelha - 14, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: geometria.altura)
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(atualAcessivel)
        .accessibilityHint("Passe o mouse ou clique para ver a carteira")
    }

    private var atualAcessivel: String {
        guard let atual = destaque, let c = atual.cotacao else { return "StockNotch" }
        return "\(atual.ativo.simbolo), \(pct(c.variacao)) hoje"
    }

    // MARK: Aberto: patrimônio e lista

    private var aberto: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("StockNotch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: geometria.largura + 16)
                Button(action: abrirPainel) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Abrir painel")
                .accessibilityLabel("Abrir painel")
            }
            .frame(height: geometria.altura)

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
    }

    private var vazio: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nenhum ativo ainda")
                .font(.system(size: 15, weight: .semibold))
            Text("Adicione ações e criptomoedas ou conecte sua conta da Binance.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Abrir painel", action: abrirPainel)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 4)
        }
    }

    private var resumo: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(carteira.totais, id: \.moeda) { total in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Patrimônio em \(total.moeda)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(dinheiro(total.patrimonio, total.moeda))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    HStack(spacing: 14) {
                        Indicador(rotulo: "Hoje", resultado: Resultado(lucro: total.hoje, percentual: total.hojePct), moeda: total.moeda)
                        if total.custo > 0 {
                            Indicador(rotulo: "Resultado", resultado: total.lucro, moeda: total.moeda)
                        }
                    }
                }
            }
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
                ForEach(binance) { LinhaNotch(linha: $0, falhou: false) }
            }
            if ocultos > 0 {
                Button("Mais \(ocultos) no painel", action: abrirPainel)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var rodape: some View {
        let aviso = carteira.erroArquivo
            ?? carteira.erroBinance.map { "Binance: \($0)" }
            ?? (carteira.simbolosSemCotacao.isEmpty ? nil : "Sem cotação: \(carteira.simbolosSemCotacao.joined(separator: ", "))")
        HStack(spacing: 6) {
            if let aviso {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(aviso).lineLimit(2)
            } else if let hora = carteira.atualizadoEm {
                Image(systemName: "arrow.clockwise")
                Text("Atualizado às \(hora.formatted(date: .omitted, time: .standard)) · B3 com 15 min de atraso")
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

    var body: some View {
        HStack(spacing: 4) {
            Text(rotulo).foregroundStyle(.secondary)
            Seta(valor: resultado.lucro).foregroundStyle(cor(resultado.lucro))
            TextoResultado(resultado: resultado, moeda: moeda)
        }
        .font(.system(size: 11, weight: .medium))
        .accessibilityElement(children: .combine)
    }
}

struct LinhaNotch: View {
    let linha: Linha
    let falhou: Bool

    var body: some View {
        HStack(spacing: 10) {
            Monograma(ativo: linha.ativo)
            VStack(alignment: .leading, spacing: 1) {
                Text(linha.ativo.simbolo).font(.system(size: 13, weight: .semibold))
                Text(linha.quantidade > 0 ? "\(qtd(linha.quantidade)) un." : "acompanhando")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let c = linha.cotacao {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(dinheiro(c.preco, c.moeda))
                        .font(.system(size: 13, weight: .medium))
                        .contentTransition(.numericText())
                    if let custo = linha.custo, linha.quantidade > 0 {
                        TextoResultado(resultado: resultado(custo: custo, valor: linha.quantidade * c.preco), moeda: c.moeda)
                            .font(.system(size: 11))
                    } else if linha.custo == nil {
                        Text(dinheiro(linha.quantidade * c.preco, c.moeda))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .monospacedDigit()
                Pilula(fracao: c.variacao)
                    .frame(width: 74, alignment: .trailing)
            } else if falhou {
                Text("sem cotação").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

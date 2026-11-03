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
                        Text(pct(abs(c.variacao), sinal: false))
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
        .accessibilityHint(tr("Passe o mouse ou clique para ver a carteira", "Hover or click to see your portfolio"))
    }

    private var atualAcessivel: String {
        guard let atual = destaque, let c = atual.cotacao else { return "StockNotch" }
        return tr("\(atual.ativo.simbolo), \(pct(c.variacao)) hoje", "\(atual.ativo.simbolo), \(pct(c.variacao)) today")
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
                .help(tr("Abrir painel", "Open StockNotch"))
                .accessibilityLabel(tr("Abrir painel", "Open StockNotch"))
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
                    Text(dinheiro(total.patrimonio, total.moeda))
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
        } else {
            let moedas = carteira.semCambio.joined(separator: ", ")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                // Câmbio velho não entra no total: melhor nenhum do que um que mistura instantes diferentes.
                if let parado = carteira.cambioParado {
                    Text(tr("Total indisponível: o câmbio de \(moedas) para \(carteira.moeda) não atualiza desde \(momento(parado)).",
                            "Total unavailable: the \(moedas) to \(carteira.moeda) exchange rate hasn't updated since \(momento(parado))."))
                } else {
                    Text(tr("Total indisponível: falta o câmbio de \(moedas) para \(carteira.moeda).",
                            "Total unavailable: no exchange rate from \(moedas) to \(carteira.moeda)."))
                }
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
                ForEach(binance) { LinhaNotch(linha: $0, falhou: false) }
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

    var body: some View {
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
                Text(situacao)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let c = linha.cotacao {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(dinheiro(c.preco, c.moeda, oculto: false))
                        .font(.system(size: 13, weight: .medium))
                        .contentTransition(.numericText())
                    // Preço na moeda do ativo; resultado e valor da posição na moeda escolhida, pela conta do total.
                    if r.custo > 0 {
                        TextoResultado(resultado: r.aberto, moeda: r.moeda)
                            .font(.system(size: 11))
                    } else if linha.quantidade > 0 {
                        // Saldo da Binance sem preço médio: só o valor.
                        Text(dinheiro(r.patrimonio, r.moeda))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if r.realizado != 0 {
                        HStack(spacing: 4) {
                            Text(tr("Realizado", "Realized")).foregroundStyle(.secondary)
                            TextoResultado(resultado: Resultado(lucro: r.realizado, percentual: 0), moeda: r.moeda, comPercentual: false)
                        }
                        .font(.system(size: 11))
                    }
                }
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
        .accessibilityElement(children: .combine)
    }
}

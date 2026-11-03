import SwiftUI

@main
struct StockNotchApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    // O notch e o painel são janelas do AppKit; esta cena vazia só satisfaz o SwiftUI
    var body: some Scene {
        Settings { EmptyView() }
            .commands { CommandGroup(replacing: .appSettings) {} }
    }
}

let intervalo: Duration = .seconds(10)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let carteira = Carteira()
    private var notch: NotchPanel?
    private var painel: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // sem ícone no Dock, como os apps de notch
        notch = NotchPanel(carteira: carteira) { [weak self] in self?.abrirPainel() }
        if carteira.ativos.isEmpty && !carteira.binanceConectada { abrirPainel() }
        Task {
            while true {
                await carteira.atualizar()
                try? await Task.sleep(for: intervalo)
            }
        }
    }

    func abrirPainel() {
        if painel == nil {
            let host = NSHostingController(rootView: PainelView().environment(carteira))
            host.sceneBridgingOptions = [.toolbars, .title]
            host.sizingOptions = [.minSize]  // a janela não encolhe abaixo do mínimo do SwiftUI
            let janela = NSWindow(contentViewController: host)
            janela.styleMask.insert(.fullSizeContentView)
            janela.toolbarStyle = .unified
            janela.setContentSize(NSSize(width: 1000, height: 600))
            janela.isReleasedWhenClosed = false
            janela.delegate = self
            janela.center()
            painel = janela
        }
        // Com o painel aberto o app aparece no Dock e no ⌘Tab; ao fechar, volta a viver só no notch.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        painel?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Formatação e peças visuais usadas no notch e no painel

func dinheiro(_ valor: Double, _ moeda: String, sinal: Bool = false) -> String {
    // Cripto barata (ex.: R$ 0,000123) precisa de mais casas.
    var estilo = FloatingPointFormatStyle<Double>.Currency(code: moeda)
        .precision(.fractionLength(valor.magnitude < 1 && valor != 0 ? 2...6 : 2...2))
    if sinal { estilo = estilo.sign(strategy: .always()) }
    return valor.formatted(estilo)
}

func pct(_ fracao: Double) -> String {
    fracao.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()))
}

func qtd(_ valor: Double) -> String {
    valor.formatted(.number.precision(.fractionLength(0...8)))
}

func cor(_ valor: Double) -> Color {
    valor > 0 ? .green : valor < 0 ? .red : .secondary
}

// Cor estável por símbolo (hashValue muda a cada execução).
func matiz(_ texto: String) -> Color {
    let h = texto.unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value }
    return Color(hue: Double(h % 360) / 360, saturation: 0.6, brightness: 0.6)
}

// Ação = quadrado arredondado, cripto = círculo.
struct Monograma: View {
    let ativo: Ativo
    var tamanho: CGFloat = 26

    var body: some View {
        let forma = ativo.cripto ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: tamanho * 0.28, style: .continuous))
        Text(ativo.simbolo.prefix(1))
            .font(.system(size: tamanho * 0.46, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: tamanho, height: tamanho)
            .background(matiz(ativo.simbolo).gradient, in: forma)
            .accessibilityHidden(true)
    }
}

struct Seta: View {
    let valor: Double

    var body: some View {
        Image(systemName: valor > 0 ? "arrowtriangle.up.fill" : valor < 0 ? "arrowtriangle.down.fill" : "minus")
            .font(.system(size: 7, weight: .bold))
            .accessibilityHidden(true)
    }
}

// Variação do dia: seta + número, além da cor (não depende só de verde/vermelho).
struct Pilula: View {
    let fracao: Double

    var body: some View {
        HStack(spacing: 3) {
            Seta(valor: fracao)
            Text(abs(fracao).formatted(.percent.precision(.fractionLength(2))))
        }
        .font(.system(size: 11, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(cor(fracao))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(cor(fracao).opacity(0.16), in: Capsule())
        .accessibilityElement()
        .accessibilityLabel("Variação \(pct(fracao))")
    }
}

struct TextoResultado: View {
    let resultado: Resultado
    let moeda: String

    var body: some View {
        Text("\(dinheiro(resultado.lucro, moeda, sinal: true)) (\(pct(resultado.percentual)))")
            .foregroundStyle(cor(resultado.lucro))
            .monospacedDigit()
    }
}

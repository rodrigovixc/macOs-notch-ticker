import SwiftUI
import UserNotifications

@main
struct StockNotchApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    // O notch e o painel são janelas do AppKit; esta cena vazia só satisfaz o SwiftUI
    var body: some Scene {
        Settings { EmptyView() }
            .commands { CommandGroup(replacing: .appSettings) {} }
    }
}

// Ações e câmbio a cada 10 s: cerca de um pedido por símbolo a cada 10 s é o que o Yahoo aguenta sem 429.
// Cripto chega pelo stream da Binance; o ciclo só a busca quando o stream não trouxe.
let intervalo: Duration = .seconds(10)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    let carteira = Carteira()
    private var notch: NotchPanel?
    private var painel: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // sem ícone no Dock, como os apps de notch
        if emPacote { UNUserNotificationCenter.current().delegate = self }
        notch = NotchPanel(carteira: carteira) { [weak self] in self?.abrirPainel() }
        if carteira.ativos.isEmpty && !carteira.binanceConectada { abrirPainel() }
        // De início a início: o tempo da busca não se soma aos 10 s.
        Task {
            while true {
                let inicio = ContinuousClock.now
                await carteira.atualizar()
                try? await Task.sleep(until: inicio + intervalo)
            }
        }
        // Sem rede o ciclo leva até ~30 s; o "agora" dos selos não pode esperar por ele.
        Task {
            while true {
                try? await Task.sleep(for: .seconds(2))
                carteira.envelhecer()
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
            janela.setContentSize(NSSize(width: 1080, height: 600))
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

    // Com o painel aberto o app está ativo, e o macOS esconderia o alerta de preço: mostra mesmo assim.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Clicar no alerta abre o painel: o app vive no notch e não teria janela para mostrar.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await abrirPainel()
    }
}

// MARK: - Formatação e peças visuais usadas no notch e no painel

// Formatadores no idioma escolhido (pt_BR: R$ 1.234,50; en_US: R$1,234.50).
// No modo privacidade os números somem e o símbolo e o sinal ficam (R$ ••••). Ocultar é o padrão, para nada
// novo vazar: só a cotação de mercado, que não diz nada da carteira, passa oculto: false.
@MainActor func dinheiro(_ valor: Double, _ moeda: String, sinal: Bool = false, oculto: Bool = Ajustes.atual.privacidade,
                         idioma: Idioma = Ajustes.atual.idioma) -> String {
    // Cripto barata (ex.: R$ 0,000123) precisa de mais casas.
    var estilo = FloatingPointFormatStyle<Double>.Currency(code: moeda, locale: idioma.locale)
        .precision(.fractionLength(valor.magnitude < 1 && valor != 0 ? 2...6 : 2...2))
    if sinal { estilo = estilo.sign(strategy: .always()) }
    let texto = valor.formatted(estilo)
    return oculto ? texto.replacing(#/\d[\d.,]*/#, with: "••••") : texto
}

@MainActor func pct(_ fracao: Double, sinal: Bool = true, idioma: Idioma = Ajustes.atual.idioma) -> String {
    var estilo = FloatingPointFormatStyle<Double>.Percent(locale: idioma.locale).precision(.fractionLength(2))
    if sinal { estilo = estilo.sign(strategy: .always()) }
    return fracao.formatted(estilo)
}

@MainActor func qtd(_ valor: Double, oculto: Bool = Ajustes.atual.privacidade, idioma: Idioma = Ajustes.atual.idioma) -> String {
    oculto ? "••••" : valor.formatted(FloatingPointFormatStyle<Double>(locale: idioma.locale).precision(.fractionLength(0...8)))
}

@MainActor func quando(_ instante: Date, data: Date.FormatStyle.DateStyle = .omitted, hora: Date.FormatStyle.TimeStyle = .omitted,
                       idioma: Idioma = Ajustes.atual.idioma) -> String {
    instante.formatted(Date.FormatStyle(date: data, time: hora, locale: idioma.locale))
}

// Só a hora quando é de hoje; de outro dia vai com a data (a cotação de sexta vista no sábado).
@MainActor func momento(_ instante: Date, agora: Date = .now, segundos: Bool = false) -> String {
    let hora: Date.FormatStyle.TimeStyle = segundos ? .standard : .shortened
    return Calendar.current.isDate(instante, inSameDayAs: agora) ? quando(instante, hora: hora) : quando(instante, data: .abbreviated, hora: hora)
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
            Text(pct(abs(fracao), sinal: false))
        }
        .font(.system(size: 11, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(cor(fracao))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(cor(fracao).opacity(0.16), in: Capsule())
        .accessibilityElement()
        .accessibilityLabel(tr("Variação \(pct(fracao))", "Change \(pct(fracao))"))
    }
}

// Idade da cotação em poucas letras ("ao vivo", "15 min", "fechado" ou o horário); parada, com o alerta.
// O texto completo vai para o VoiceOver e para a dica.
struct SeloCotacao: View {
    let cotacao: Cotacao
    let agora: Date

    var body: some View {
        let selo = cotacao.selo(agora: agora)
        // Preço fixo (BRL, USDT) não tem idade: nada de selo, muito menos "ao vivo".
        if selo != .fixo {
            rotulo(selo)
        }
    }

    private func rotulo(_ selo: Selo) -> some View {
        HStack(spacing: 3) {
            switch selo {
            case .aoVivo:
                Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.green)
                Text(tr("ao vivo", "live"))
            case .atraso(let atraso):
                Image(systemName: "clock")
                Text("\(Int(atraso / 60)) min")
            case .fechado:
                Text(tr("fechado", "closed"))
            case .velho(let desde):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(momento(desde, agora: agora))
            case .horario(let em):
                Text(momento(em, agora: agora))
            case .fixo:
                EmptyView()
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(descricao(selo))
        .help(descricao(selo))
    }

    private func descricao(_ selo: Selo) -> String {
        let hora = momento(cotacao.em, agora: agora, segundos: true)
        switch selo {
        case .aoVivo:
            return tr("Ao vivo, cotação das \(hora)", "Live, quote from \(hora)")
        case .atraso(let atraso):
            return tr("Fonte com \(Int(atraso / 60)) min de atraso, cotação das \(hora)", "Source delayed \(Int(atraso / 60)) min, quote from \(hora)")
        case .fechado:
            return tr("Mercado fechado, última cotação das \(hora)", "Market closed, last quote from \(hora)")
        case .velho(let desde):
            return tr("Sem atualizar desde \(momento(desde, agora: agora)), cotação das \(hora)",
                      "Not updated since \(momento(desde, agora: agora)), quote from \(hora)")
        case .horario:
            return tr("Cotação das \(hora)", "Quote from \(hora)")
        case .fixo:
            return tr("Preço fixo", "Fixed price")
        }
    }
}

// Sem percentual para o realizado: o app não guarda sobre que custo ele foi apurado.
struct TextoResultado: View {
    let resultado: Resultado
    let moeda: String
    var comPercentual = true

    var body: some View {
        let valor = dinheiro(resultado.lucro, moeda, sinal: true)
        Text(comPercentual ? "\(valor) (\(pct(resultado.percentual)))" : valor)
            .foregroundStyle(cor(resultado.lucro))
            .monospacedDigit()
    }
}

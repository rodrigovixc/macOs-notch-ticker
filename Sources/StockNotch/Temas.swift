import Charts
import SwiftUI

// Temas: cada um é um design system (estilo, cores, tipografia, raio, superfície, densidade e layout da Visão geral),
// tirado da biblioteca ui-ux-pro-max para um app de finanças e traduzido para o macOS: fontes do sistema no lugar de
// fontes da web (Inter → SF, JetBrains Mono → SF Mono, Playfair → New York, Plus Jakarta → SF Rounded).
// Alta e baixa continuam verde e vermelho em todos (são significado), e as cores das classes na alocação não mudam.
enum Tema: String, CaseIterable, Identifiable {
    case padrao, aurora, swiss, terminal, neon, luxo, suave, meiaNoite
    var id: Self { self }

    @MainActor var nome: String {
        switch self {
        case .padrao: "Liquid Glass"
        case .aurora: "Aurora"
        case .swiss: "Swiss"
        case .terminal: "Terminal"
        case .neon: "Neon"
        case .luxo: tr("Luxo", "Luxury")
        case .suave: tr("Suave", "Soft")
        case .meiaNoite: tr("Meia-noite", "Midnight")
        }
    }

    // Em uma linha, o que o define (aparece embaixo do nome no seletor).
    @MainActor var descricao: String {
        switch self {
        case .padrao: tr("Vidro do macOS", "macOS glass")
        case .aurora: tr("Vidro com gradiente", "Gradient glass")
        case .swiss: tr("Minimalismo suíço", "Swiss minimalism")
        case .terminal: tr("Denso, monoespaçado", "Dense, monospaced")
        case .neon: "Cyberpunk"
        case .luxo: tr("Preto e dourado, serifa", "Black and gold, serif")
        case .suave: tr("Neumorfismo claro", "Light neumorphism")
        case .meiaNoite: tr("Fintech escuro", "Dark fintech")
        }
    }

    var estilo: EstiloVisual {
        switch self {
        case .padrao:
            EstiloVisual(destaque: .accentColor, linha: Color(claro: 0x2A78D6, escuro: 0x3987E5), fonte: .default, fonteTitulo: .default,
                         raio: 16, superficie: .vidro, espaco: 16, respiro: 16, esquema: nil, fundo: .vidro(veu: []),
                         layout: .cartoes, widget: [.black])
        case .aurora:
            EstiloVisual(destaque: Color(hex: 0xA855F7), linha: Color(hex: 0xC084FC), fonte: .rounded, fonteTitulo: .rounded,
                         raio: 22, superficie: .vidro, espaco: 18, respiro: 18, esquema: .dark,
                         fundo: .vidro(veu: [Color(hex: 0x6D28D9).opacity(0.38), Color(hex: 0xDB2777).opacity(0.26)]),
                         layout: .cartoes, widget: [.black, Color(hex: 0x3B0764)])
        case .swiss:
            EstiloVisual(destaque: Color(hex: 0x2563EB), linha: Color(hex: 0x18181B), fonte: .default, fonteTitulo: .default,
                         raio: 4, superficie: .solida(fundo: .white, borda: Color(hex: 0xE4E4E7)), espaco: 24, respiro: 20,
                         esquema: .light, fundo: .cor(Color(hex: 0xFAFAFA)), layout: .editorial, widget: [.black, Color(hex: 0x18181B)])
        case .terminal:
            EstiloVisual(destaque: Color(hex: 0x22C55E), linha: Color(hex: 0x22C55E), fonte: .monospaced, fonteTitulo: .monospaced,
                         raio: 2, superficie: .solida(fundo: Color(hex: 0x0B1220), borda: Color(hex: 0x1E293B)), espaco: 8, respiro: 10,
                         esquema: .dark, fundo: .cor(Color(hex: 0x020617)), layout: .compacto, widget: [.black, Color(hex: 0x03140A)],
                         interpolacao: .linear)
        case .neon:
            EstiloVisual(destaque: Color(hex: 0x22D3EE), linha: Color(hex: 0xF0ABFC), fonte: .monospaced, fonteTitulo: .monospaced,
                         raio: 4, superficie: .neon(fundo: Color(hex: 0x111127), borda: Color(hex: 0xA855F7)), espaco: 14, respiro: 14,
                         esquema: .dark, fundo: .cor(Color(hex: 0x0A0A1A)), layout: .cartoes, widget: [.black, Color(hex: 0x1E0B3A)])
        case .luxo:
            EstiloVisual(destaque: Color(hex: 0xCA8A04), linha: Color(hex: 0xD4A017), fonte: .default, fonteTitulo: .serif,
                         raio: 12, superficie: .solida(fundo: Color(hex: 0x1C1917), borda: Color(hex: 0xA16207).opacity(0.55)),
                         espaco: 20, respiro: 20, esquema: .dark, fundo: .cor(Color(hex: 0x0C0A09)), layout: .editorial,
                         widget: [.black, Color(hex: 0x292524)])
        case .suave:
            EstiloVisual(destaque: Color(hex: 0x0891B2), linha: Color(hex: 0x0891B2), fonte: .rounded, fonteTitulo: .rounded,
                         raio: 20, superficie: .neumorfica(base: Color(hex: 0xE6EBF1)), espaco: 22, respiro: 18,
                         esquema: .light, fundo: .cor(Color(hex: 0xE6EBF1)), layout: .cartoes, widget: [.black, Color(hex: 0x0E3A47)])
        case .meiaNoite:
            EstiloVisual(destaque: Color(hex: 0xF59E0B), linha: Color(hex: 0xFBBF24), fonte: .default, fonteTitulo: .default,
                         raio: 10, superficie: .solida(fundo: Color(hex: 0x1E293B), borda: Color(hex: 0x334155)), espaco: 12, respiro: 14,
                         esquema: .dark, fundo: .cor(Color(hex: 0x0F172A)), layout: .compacto, widget: [.black, Color(hex: 0x1E293B)])
        }
    }

    // Atalhos usados fora daqui.
    var destaque: Color { estilo.destaque }
    var widget: [Color] { estilo.widget }
}

// Os tokens de um design system.
struct EstiloVisual {
    enum Superficie {
        case vidro                                   // Liquid Glass (material antes do macOS 26)
        case solida(fundo: Color, borda: Color)      // cartão chapado com fio
        case neon(fundo: Color, borda: Color)        // fio colorido com brilho
        case neumorfica(base: Color)                 // mesma cor do fundo, relevo por duas sombras
    }
    enum Fundo {
        case vidro(veu: [Color])  // a janela translúcida, com um véu de cor por cima
        case cor(Color)           // chapado
    }
    // Como a Visão geral se arranja: cartões em grade, compacto (denso, tudo menor) ou editorial (número grande,
    // seções corridas com fios, sem cartões).
    enum Layout { case cartoes, compacto, editorial }

    var destaque: Color
    var linha: Color
    var fonte: Font.Design
    var fonteTitulo: Font.Design
    var raio: CGFloat
    var superficie: Superficie
    var espaco: CGFloat
    var respiro: CGFloat
    var esquema: ColorScheme?
    var fundo: Fundo
    var layout: Layout
    var widget: [Color]
    var interpolacao: InterpolationMethod = .monotone
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// Superfície de um cartão pelo tema: vidro, chapada, neon ou neumórfica.
struct FundoCartao: ViewModifier {
    var raio: CGFloat?

    func body(content: Content) -> some View {
        let estilo = Ajustes.atual.tema.estilo
        let forma = RoundedRectangle(cornerRadius: raio ?? estilo.raio, style: .continuous)
        switch estilo.superficie {
        case .vidro:
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: forma)
            } else {
                content.background(.regularMaterial, in: forma)
            }
        case .solida(let fundo, let borda):
            content.background(fundo, in: forma).overlay(forma.strokeBorder(borda, lineWidth: 1))
        case .neon(let fundo, let borda):
            content.background(fundo, in: forma)
                .overlay(forma.strokeBorder(borda.opacity(0.9), lineWidth: 1))
                .shadow(color: borda.opacity(0.45), radius: 8)
        case .neumorfica(let base):
            content.background(base, in: forma)
                .shadow(color: .white.opacity(0.9), radius: 8, x: -5, y: -5)
                .shadow(color: Color(hex: 0xA3B1C6).opacity(0.6), radius: 8, x: 5, y: 5)
        }
    }
}

// Fundo da janela do painel pelo tema.
struct FundoDoPainel: View {
    var body: some View {
        switch Ajustes.atual.tema.estilo.fundo {
        case .vidro(let veu):
            ZStack {
                FundoDeVidro()
                LinearGradient(colors: veu, startPoint: .top, endPoint: .bottom)
            }
        case .cor(let cor):
            cor
        }
    }
}

// Escolha de tema em Ajustes: uma miniatura de cada design system (fundo, cartão, destaque e fonte dele).
struct SeletorDeTema: View {
    @Bindable var ajustes: Ajustes

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 14)], spacing: 14) {
            ForEach(Tema.allCases) { tema in
                let escolhido = ajustes.tema == tema
                Button { ajustes.tema = tema } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Miniatura(estilo: tema.estilo)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(escolhido ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: escolhido ? 2.5 : 1)
                            }
                        HStack(spacing: 4) {
                            if escolhido { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                            Text(tema.nome).font(.callout.weight(.medium))
                        }
                        Text(tema.descricao).font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tema.nome), \(tema.descricao)")
                .accessibilityAddTraits(escolhido ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

private struct Miniatura: View {
    let estilo: EstiloVisual

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                switch estilo.fundo {
                case .vidro(let veu): LinearGradient(colors: veu.isEmpty ? [Color(white: 0.32), Color(white: 0.22)] : veu.map { $0.opacity(1) },
                                                     startPoint: .top, endPoint: .bottom)
                case .cor(let cor): cor
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Aa").font(.system(size: 15, weight: .semibold, design: estilo.fonteTitulo))
                RoundedRectangle(cornerRadius: min(estilo.raio, 6)).fill(estilo.destaque).frame(width: 34, height: 6)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 14)); p.addLine(to: CGPoint(x: 14, y: 9)); p.addLine(to: CGPoint(x: 28, y: 12))
                    p.addLine(to: CGPoint(x: 44, y: 3)); p.addLine(to: CGPoint(x: 60, y: 5))
                }
                .stroke(estilo.linha, lineWidth: 1.5)
                .frame(width: 60, height: 16)
            }
            .padding(8)
            .modifier(MiniCartao(estilo: estilo))
            .padding(8)
        }
        .foregroundStyle(estilo.esquema == .light ? Color.black : .white)
        .frame(height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MiniCartao: ViewModifier {
    let estilo: EstiloVisual

    func body(content: Content) -> some View {
        let forma = RoundedRectangle(cornerRadius: min(estilo.raio, 10), style: .continuous)
        switch estilo.superficie {
        case .vidro: content.background(.white.opacity(0.12), in: forma)
        case .solida(let fundo, let borda): content.background(fundo, in: forma).overlay(forma.strokeBorder(borda))
        case .neon(let fundo, let borda): content.background(fundo, in: forma).overlay(forma.strokeBorder(borda)).shadow(color: borda.opacity(0.6), radius: 4)
        case .neumorfica(let base):
            content.background(base, in: forma)
                .shadow(color: .white.opacity(0.9), radius: 3, x: -2, y: -2)
                .shadow(color: Color(hex: 0xA3B1C6).opacity(0.7), radius: 3, x: 2, y: 2)
        }
    }
}

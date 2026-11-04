import SwiftUI

// Temas: a cor de destaque (botões, seleção, linha do patrimônio), um véu de cor sobre o vidro da janela e o fundo
// do widget. Alta e baixa continuam verde e vermelho em todos (são significado, não enfeite), e as cores das
// classes na alocação também não mudam, para o B3 ser sempre o azul.
enum Tema: String, CaseIterable, Identifiable {
    case padrao, grafite, oceano, aurora, porDoSol, floresta
    var id: Self { self }

    @MainActor var nome: String {
        switch self {
        case .padrao: tr("Padrão", "Default")
        case .grafite: tr("Grafite", "Graphite")
        case .oceano: tr("Oceano", "Ocean")
        case .aurora: "Aurora"
        case .porDoSol: tr("Pôr do sol", "Sunset")
        case .floresta: tr("Floresta", "Forest")
        }
    }

    var destaque: Color {
        switch self {
        case .padrao: .accentColor
        case .grafite: Color(hex: 0xA1A1AA)
        case .oceano: Color(hex: 0x0EA5E9)
        case .aurora: Color(hex: 0xA855F7)
        case .porDoSol: Color(hex: 0xF97316)
        case .floresta: Color(hex: 0x10B981)
        }
    }

    // Por cima do vidro da janela, de cima para baixo. Leve: o texto continua no contraste do sistema.
    var veu: [Color] {
        switch self {
        case .padrao: []
        case .grafite: [.black.opacity(0.28), .black.opacity(0.18)]
        case .oceano: [Color(hex: 0x0B3D91).opacity(0.32), Color(hex: 0x0E7490).opacity(0.22)]
        case .aurora: [Color(hex: 0x6D28D9).opacity(0.30), Color(hex: 0xDB2777).opacity(0.20)]
        case .porDoSol: [Color(hex: 0x9A3412).opacity(0.30), Color(hex: 0xBE185D).opacity(0.20)]
        case .floresta: [Color(hex: 0x065F46).opacity(0.32), Color(hex: 0x3F6212).opacity(0.20)]
        }
    }

    // Fundo do widget, escuro para o texto branco: começa preto no topo (some no notch) e ganha a cor embaixo.
    var widget: [Color] {
        switch self {
        case .padrao: [.black]
        case .grafite: [.black, Color(hex: 0x27272A)]
        case .oceano: [.black, Color(hex: 0x0B2545)]
        case .aurora: [.black, Color(hex: 0x3B0764)]
        case .porDoSol: [.black, Color(hex: 0x4A1504)]
        case .floresta: [.black, Color(hex: 0x052E1F)]
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// Escolha de tema em Ajustes: uma amostra de cada, com o fundo do widget e a cor de destaque.
struct SeletorDeTema: View {
    @Bindable var ajustes: Ajustes

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
            ForEach(Tema.allCases) { tema in
                let escolhido = ajustes.tema == tema
                Button { ajustes.tema = tema } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottomTrailing) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LinearGradient(colors: tema.widget.count > 1 ? tema.widget : [.black, Color(white: 0.15)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(height: 54)
                                .overlay(alignment: .topLeading) {
                                    Text("PETR4 ▲ 1,2%").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white).padding(7)
                                }
                            Circle().fill(tema.destaque).frame(width: 14, height: 14).padding(7)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(escolhido ? tema.destaque : Color.secondary.opacity(0.25), lineWidth: escolhido ? 2 : 1)
                        }
                        HStack(spacing: 4) {
                            if escolhido { Image(systemName: "checkmark.circle.fill").foregroundStyle(tema.destaque) }
                            Text(tema.nome).font(.callout)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tema.nome)
                .accessibilityAddTraits(escolhido ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

import Foundation
import Observation

enum Idioma: String, CaseIterable, Identifiable {
    case pt, en
    var id: Self { self }
    var locale: Locale { Locale(identifier: self == .pt ? "pt_BR" : "en_US") }
    // Cada idioma escrito nele mesmo, como no macOS: quem não lê o atual ainda acha o seu.
    var nome: String { self == .pt ? "Português (Brasil)" : "English" }
}

enum Moeda: String, CaseIterable, Identifiable {
    case BRL, USD, EUR
    var id: Self { self }
}

// Onde o widget fica: grudado no notch (topo da tela, ao centro) ou solto, onde a pessoa arrastar.
enum PosicaoWidget: String, CaseIterable, Identifiable {
    case notch, livre
    var id: Self { self }
}

// O que o widget fechado mostra: um ativo de cada vez (variação, cotação ou as duas) ou o total, sem girar.
enum EstiloWidget: String, CaseIterable, Identifiable {
    case variacao, preco, completo, total
    var id: Self { self }
}

// Preferências do usuário, guardadas no UserDefaults. Uma instância só (atual), no MainActor como as views:
// os formatadores leem daqui e o Observation redesenha o notch e o painel abertos quando algo muda.
@MainActor @Observable
final class Ajustes {
    static let atual = Ajustes()

    var idioma: Idioma {
        didSet {
            defaults.set(idioma.rawValue, forKey: "idioma")
            // Menus e diálogos do sistema seguem o AppleLanguages do app, que o macOS só lê no início.
            defaults.set([idioma == .pt ? "pt-BR" : "en"], forKey: "AppleLanguages")
        }
    }

    var moeda: Moeda {
        didSet { defaults.set(moeda.rawValue, forKey: "moeda") }
    }

    // Esconde valores e quantidades (R$ ••••) no notch e no painel, para mostrar a tela sem expor a carteira.
    var privacidade: Bool {
        didSet { defaults.set(privacidade, forKey: "privacidade") }
    }

    var posicao: PosicaoWidget {
        didSet { defaults.set(posicao.rawValue, forKey: "posicao") }
    }

    // Widget de vidro (Liquid Glass, macOS 26 em diante) quando não está colado a um notch de verdade.
    var vidro: Bool {
        didSet { defaults.set(vidro, forKey: "vidro") }
    }

    var tema: Tema {
        didSet { defaults.set(tema.rawValue, forKey: "tema") }
    }

    var estilo: EstiloWidget {
        didSet { defaults.set(estilo.rawValue, forKey: "estilo") }
    }

    // Quantos ativos o widget fechado mostra lado a lado (1 a 4).
    var quantos: Int {
        didSet { defaults.set(quantos, forKey: "quantos") }
    }

    // Com vários ao mesmo tempo, metade ações e metade cripto (cada metade gira por conta própria).
    var dividir: Bool {
        didSet { defaults.set(dividir, forKey: "dividir") }
    }

    // Segundos de cada ativo no letreiro do widget fechado.
    var ritmo: Int {
        didSet { defaults.set(ritmo, forKey: "ritmo") }
    }

    // Linha.id do que não gira no letreiro. Guarda a exclusão, não a escolha: ativo novo entra girando.
    var foraDoLetreiro: Set<String> {
        didSet { defaults.set(foraDoLetreiro.sorted(), forKey: "foraDoLetreiro") }
    }

    // Coluna de últimas notícias ao lado da carteira no widget aberto.
    var noticias: Bool {
        didSet { defaults.set(noticias, forKey: "noticias") }
    }

    // Ativo.id → moeda em que a linha dele aparece (BRL, USD, EUR). Sem entrada, a própria do ativo. Os totais
    // seguem a moeda acima: somar reais com dólares só dá certo numa moeda só.
    var moedaDoAtivo: [String: String] {
        didSet { defaults.set(moedaDoAtivo, forKey: "moedaDoAtivo") }
    }

    // Topo e centro do widget solto, em coordenadas de tela; nil é o topo da tela principal.
    var ancoraLivre: CGPoint? {
        didSet { defaults.set(ancoraLivre.map { [$0.x, $0.y] }, forKey: "ancoraLivre") }
    }

    @ObservationIgnored private let defaults: UserDefaults

    // Sem escolha salva, segue a primeira língua do sistema.
    init(defaults: UserDefaults = .standard, linguas: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        let sistema: Idioma = linguas.first?.hasPrefix("pt") == true ? .pt : .en
        let idioma = defaults.string(forKey: "idioma").flatMap(Idioma.init) ?? sistema
        self.idioma = idioma
        moeda = defaults.string(forKey: "moeda").flatMap(Moeda.init) ?? (idioma == .pt ? .BRL : .USD)
        privacidade = defaults.bool(forKey: "privacidade")
        posicao = defaults.string(forKey: "posicao").flatMap(PosicaoWidget.init) ?? .notch
        estilo = defaults.string(forKey: "estilo").flatMap(EstiloWidget.init) ?? .variacao
        vidro = defaults.object(forKey: "vidro") as? Bool ?? true
        tema = defaults.string(forKey: "tema").flatMap(Tema.init) ?? .padrao
        ritmo = defaults.object(forKey: "ritmo") as? Int ?? 4
        quantos = defaults.object(forKey: "quantos") as? Int ?? 1
        dividir = defaults.bool(forKey: "dividir")
        foraDoLetreiro = Set(defaults.stringArray(forKey: "foraDoLetreiro") ?? [])
        noticias = defaults.bool(forKey: "noticias")
        moedaDoAtivo = defaults.dictionary(forKey: "moedaDoAtivo") as? [String: String] ?? [:]
        ancoraLivre = (defaults.array(forKey: "ancoraLivre") as? [Double]).flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
    }
}

// Abrir com o Mac e as notificações precisam do pacote .app: com swift run não há app para o macOS registrar.
let emPacote = Bundle.main.bundleURL.pathExtension == "app"

// Texto da interface no idioma escolhido. Sem arquivos de tradução: os dois textos ficam onde são usados.
@MainActor func tr(_ pt: String, _ en: String, idioma: Idioma = Ajustes.atual.idioma) -> String {
    idioma == .pt ? pt : en
}

// Falha guarda os dois textos e só escolhe ao mostrar: trocar o idioma traduz até o aviso já na tela.
// Erros do sistema ganham texto próprio: o localizedDescription viria no idioma em que o app abriu.
@MainActor func mensagem(_ erro: any Error, idioma: Idioma = Ajustes.atual.idioma) -> String {
    let t = { (pt: String, en: String) in tr(pt, en, idioma: idioma) }
    switch erro {
    case let f as Falha:
        return t(f.pt, f.en)
    case let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(e.code):
        return t("Sem conexão com a internet.", "No internet connection.")
    case let e as URLError where e.code == .timedOut:
        return t("O serviço demorou demais para responder.", "The service took too long to respond.")
    case let e as URLError:
        return t("Não consegui falar com o serviço (erro \(e.code.rawValue)).", "Couldn't reach the service (error \(e.code.rawValue)).")
    case is DecodingError:
        return t("O serviço respondeu num formato inesperado.", "The service sent an unexpected response.")
    default:
        let ns = erro as NSError
        return t("Erro inesperado (\(ns.domain) \(ns.code)).", "Unexpected error (\(ns.domain) \(ns.code)).")
    }
}

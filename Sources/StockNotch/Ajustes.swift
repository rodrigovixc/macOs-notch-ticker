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

    @ObservationIgnored private let defaults: UserDefaults

    // Sem escolha salva, segue a primeira língua do sistema.
    init(defaults: UserDefaults = .standard, linguas: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        let sistema: Idioma = linguas.first?.hasPrefix("pt") == true ? .pt : .en
        let idioma = defaults.string(forKey: "idioma").flatMap(Idioma.init) ?? sistema
        self.idioma = idioma
        moeda = defaults.string(forKey: "moeda").flatMap(Moeda.init) ?? (idioma == .pt ? .BRL : .USD)
    }
}

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

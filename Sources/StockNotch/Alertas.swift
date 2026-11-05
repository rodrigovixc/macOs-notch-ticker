import Foundation
import UserNotifications

// Alerta de preço de um ativo, guardado com ele no carteira.json.
struct Alerta: Codable, Identifiable, Hashable {
    enum Tipo: String, Codable, CaseIterable {
        case acima, abaixo, variacao
    }

    var id = UUID()
    var tipo: Tipo
    var valor: Double      // preço em `moeda`; na variação, a fração (0.05 = ±5%)
    var moeda: String      // a do preço quando o alerta foi criado: cripto em R$ ou US$ não muda com a moeda escolhida
    var disparado = false  // já avisou e o preço ainda não voltou para o outro lado; salvo para não repetir ao reabrir o app
    var avisouEm: Date?    // variação: o horário da cotação que avisou; opcional no JSON (alertas de antes não têm)

    // Folga para rearmar: o preço tem que voltar 0,1% além do alvo (na variação, 0,1 ponto). Sem ela, cripto
    // oscilando em cima do alvo (um tick a cada 2 s) daria uma notificação atrás da outra.
    static let folga = 0.001

    // Quanto a cotação passou do alvo (≥ 0: atingido), relativo ao preço ou em pontos de variação.
    func distancia(_ c: Cotacao) -> Double {
        switch tipo {
        case .acima: c.preco / valor - 1
        case .abaixo: 1 - c.preco / valor
        case .variacao: abs(c.variacao) - valor
        }
    }

    // true quando deve notificar agora: atingiu estando armado. Rearma ao voltar para o outro lado e, na variação,
    // também quando a cotação passa a ser de um dia (pregão, ou 00:00 UTC na cripto) que começou depois do aviso:
    // abrir com +6% depois de um dia de +6% é outro aviso. Antes da abertura a cotação ainda é do pregão anterior
    // (início do dia sem limite) e não rearma.
    mutating func conferir(_ c: Cotacao) -> Bool {
        guard valor > 0 else { return false }
        if tipo == .variacao, disparado, let avisouEm, c.inicioDoDia > avisouEm { disparado = false }
        let d = distancia(c)
        if d >= 0 && !disparado {
            disparado = true
            if tipo == .variacao { avisouEm = c.em }
            return true
        }
        if d < -Self.folga { disparado = false }
        return false
    }
}

extension Snapshot {
    // A cotação na moeda do alerta (cripto em R$ ou em US$, a que ele gravou), não na moeda escolhida agora.
    // Moeda diferente (cripto sem par em USDT, alerta em US$) ou preço fixo: nada a conferir.
    func cotacao(para alerta: Alerta, de ativo: Ativo) -> Cotacao? {
        guard let c = cotacao(ativo, moeda: alerta.moeda), c.moeda == alerta.moeda, !c.fixa else { return nil }
        return c
    }
}

// Notificações nativas. Sem o pacote .app (swift run, testes) o UNUserNotificationCenter derruba o processo:
// tudo aqui confere emPacote antes.
enum Notificacoes {
    // O sistema só pergunta enquanto o usuário não decidiu; depois devolve a resposta salva sem perguntar.
    static func pedirPermissao() async {
        guard emPacote else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func autorizacao() async -> UNAuthorizationStatus {
        guard emPacote else { return .notDetermined }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // O id do alerta como identificador: disparar de novo substitui o aviso anterior na Central de Notificações.
    static func enviar(id: UUID, titulo: String, corpo: String) {
        guard emPacote else { return }
        let conteudo = UNMutableNotificationContent()
        conteudo.title = titulo
        conteudo.body = corpo
        conteudo.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id.uuidString, content: conteudo, trigger: nil))
    }

    // Ajustes do Sistema > Notificações > StockNotch.
    static var ajustesDoSistema: URL? {
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")
    }
}

extension Alerta {
    // Como o alerta aparece na lista e na notificação. Preços de mercado não são dados do usuário: nunca ocultos.
    @MainActor var descricao: String {
        let alvo = dinheiro(valor, moeda, oculto: false)
        switch tipo {
        case .acima: return tr("Acima de \(alvo)", "Above \(alvo)")
        case .abaixo: return tr("Abaixo de \(alvo)", "Below \(alvo)")
        case .variacao: return tr("Variação do dia de ±\(pct(valor, sinal: false))", "Daily change of ±\(pct(valor, sinal: false))")
        }
    }

    @MainActor func notificar(_ simbolo: String, _ c: Cotacao) {
        let dia = pct(abs(c.variacao), sinal: false)
        let titulo = tipo != .variacao ? "\(simbolo): \(descricao)"
            : c.variacao >= 0 ? tr("\(simbolo) sobe \(dia) hoje", "\(simbolo) up \(dia) today") : tr("\(simbolo) cai \(dia) hoje", "\(simbolo) down \(dia) today")
        let preco = dinheiro(c.preco, c.moeda, oculto: false)
        Notificacoes.enviar(id: id, titulo: titulo, corpo: tr("Cotação: \(preco) (\(pct(c.variacao)) hoje)", "Price: \(preco) (\(pct(c.variacao)) today)"))
    }
}

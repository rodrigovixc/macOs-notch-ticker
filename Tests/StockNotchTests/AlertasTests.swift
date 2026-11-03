import Foundation
import Testing
@testable import StockNotch

private func preco(_ p: Double, variacao: Double = 0) -> Cotacao { Cotacao(preco: p, variacao: variacao, moeda: "BRL") }

// Passa uma sequência de cotações pelo alerta e diz em quais ele notificou.
private func disparos(_ alerta: inout Alerta, _ cotacoes: [Cotacao]) -> [Bool] {
    cotacoes.map { alerta.conferir($0) }
}

@Test func alertaAcimaDisparaUmaVezPorCruzamento() {
    var alerta = Alerta(tipo: .acima, valor: 50, moeda: "BRL")
    var r: [Bool]
    // Abaixo não avisa; cruzou, avisa uma vez; continuar acima não repete.
    r = disparos(&alerta, [preco(49), preco(50), preco(51), preco(50.5)])
    #expect(r == [false, true, false, false])
    #expect(alerta.disparado)
    // Voltar só um pouco (dentro da folga de 0,1%) não rearma: cripto oscilando no alvo não vira enxurrada.
    r = disparos(&alerta, [preco(49.96), preco(50.01)])
    #expect(r == [false, false])
    // Voltou de verdade para o outro lado: rearma e avisa no próximo cruzamento.
    r = disparos(&alerta, [preco(49.9)])
    #expect(r == [false])
    #expect(!alerta.disparado)
    r = disparos(&alerta, [preco(50.2)])
    #expect(r == [true])
}

@Test func alertaAbaixoEJaAtingidoAoCriar() {
    var alerta = Alerta(tipo: .abaixo, valor: 40, moeda: "BRL")
    var r: [Bool]
    // Criado com a cotação já abaixo: avisa na primeira conferência (está armado).
    r = disparos(&alerta, [preco(39), preco(38), preco(40.1), preco(39.9)])
    #expect(r == [true, false, false, true])
}

@Test func alertaDeVariacaoNosDoisSentidos() {
    var alerta = Alerta(tipo: .variacao, valor: 0.05, moeda: "BRL")  // ±5%
    var r: [Bool]
    r = disparos(&alerta, [preco(10, variacao: 0.049), preco(10, variacao: 0.051)])
    #expect(r == [false, true])
    // De +5,1% para −5,2% sem voltar abaixo de 5%: o mesmo dia, um aviso só.
    r = disparos(&alerta, [preco(10, variacao: -0.052)])
    #expect(r == [false])
    // Rearma abaixo de 4,9% e avisa na queda.
    r = disparos(&alerta, [preco(10, variacao: -0.03), preco(10, variacao: -0.06)])
    #expect(r == [false, true])
}

@Test func alertaInvalidoNaoDispara() {
    // Valor zero só vem de JSON editado à mão: nada de divisão por zero nem aviso.
    var alerta = Alerta(tipo: .acima, valor: 0, moeda: "BRL")
    let disparou = alerta.conferir(preco(10))
    #expect(!disparou)
    #expect(!alerta.disparado)
}

// Cada alerta confere a cotação na moeda que gravou, não na escolhida agora: trocar de moeda não muda o alvo.
@Test func alertaUsaACotacaoNaMoedaDele() {
    let agora = Date(timeIntervalSince1970: 10_000)
    var fontes = Fontes()
    fontes.acoes["a:PETR4"] = Cotacao(preco: 50, variacao: 0, moeda: "BRL", recebida: agora)
    fontes.cripto["c:BTC"] = Cotacao(preco: 78_000, variacao: 0, moeda: "USD", recebida: agora)
    fontes.cambio["USD"] = Cotacao(preco: 5.5, variacao: 0, moeda: "BRL", recebida: agora)
    let s = Snapshot(fontes, agora: agora)
    let btc = Ativo(simbolo: "BTC", cripto: true)
    #expect(s.cotacao(para: Alerta(tipo: .acima, valor: 1, moeda: "BRL"), de: btc)?.preco == 78_000 * 5.5)
    #expect(s.cotacao(para: Alerta(tipo: .acima, valor: 1, moeda: "USD"), de: btc)?.preco == 78_000)
    #expect(s.cotacao(para: Alerta(tipo: .acima, valor: 1, moeda: "BRL"), de: Ativo(simbolo: "PETR4", cripto: false))?.preco == 50)
    // Moeda que não bate e preço fixo não conferem nada.
    #expect(s.cotacao(para: Alerta(tipo: .acima, valor: 1, moeda: "USD"), de: Ativo(simbolo: "PETR4", cripto: false)) == nil)
    #expect(s.cotacao(para: Alerta(tipo: .acima, valor: 1, moeda: "USD"), de: Ativo(simbolo: "USDT", cripto: true)) == nil)
}

// Os alertas vão no carteira.json; os arquivos de antes deles continuam legíveis.
@Test func alertasNoArquivo() throws {
    let antigo = #"[{"simbolo":"PETR4","cripto":false,"compras":[]}]"#
    #expect(try Arquivo.ler(Data(antigo.utf8)).ativos.first?.alertas == [])
    let semAlertas = #"{"ativos":[{"simbolo":"BTC","cripto":true,"compras":[],"vendas":[]}],"precoMedioBinance":{}}"#
    #expect(try Arquivo.ler(Data(semAlertas.utf8)).ativos.first?.alertas == [])

    // O estado de disparado vai junto: reabrir o app não repete o aviso.
    let alertas = [Alerta(tipo: .acima, valor: 55.2, moeda: "BRL", disparado: true), Alerta(tipo: .variacao, valor: 0.05, moeda: "USD")]
    let novo = Arquivo(ativos: [Ativo(simbolo: "PETR4", cripto: false, alertas: alertas)])
    #expect(try Arquivo.ler(novo.dados()) == novo)
}

// O ICU separa o símbolo com espaço inseparável em pt_BR; troca por espaço comum para comparar.
@MainActor @Test func modoPrivacidadeEscondeValores() {
    let simples = { (texto: String) in texto.replacingOccurrences(of: "\u{00A0}", with: " ") }
    #expect(simples(dinheiro(1234.5, "BRL", oculto: true, idioma: .pt)) == "R$ ••••")
    #expect(simples(dinheiro(-10, "USD", sinal: true, oculto: true, idioma: .pt)) == "-US$ ••••")
    #expect(dinheiro(0.000123, "BRL", oculto: true, idioma: .en) == "R$••••")
    #expect(dinheiro(1234.5, "USD", oculto: true, idioma: .en) == "$••••")
    #expect(qtd(0.05, oculto: true, idioma: .pt) == "••••")
    // Desligado, nada muda; percentuais nunca são ocultos.
    #expect(simples(dinheiro(1234.5, "BRL", oculto: false, idioma: .pt)) == "R$ 1.234,50")
    #expect(qtd(1234.5, oculto: false, idioma: .en) == "1,234.5")
    #expect(pct(0.0123, idioma: .pt) == "+1,23%")
}

// Usa um domínio próprio do UserDefaults para não tocar nos ajustes do app.
@MainActor @Test func modoPrivacidadePersistido() throws {
    let dominio = "StockNotchTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: dominio))
    defer { defaults.removePersistentDomain(forName: dominio) }

    let ajustes = Ajustes(defaults: defaults, linguas: ["pt-BR"])
    #expect(!ajustes.privacidade)  // desligado por padrão
    ajustes.privacidade = true
    #expect(Ajustes(defaults: defaults, linguas: ["pt-BR"]).privacidade)
}

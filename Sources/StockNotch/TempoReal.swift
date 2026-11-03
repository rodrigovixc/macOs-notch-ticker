import Foundation

// Mensagem do stream combinado da Binance: {"stream": "btcusdt@kline_1d", "data": {...}}. O serverShutdown também
// é aceito sem o envelope: a documentação mostra os dois formatos e não deu para capturar um de verdade.
enum MensagemBinance: Equatable {
    case cotacao(moeda: String, Cotacao)  // em dólares (par em USDT)
    case desligando                       // serverShutdown: a Binance vai derrubar a conexão

    // nil para o que não interessa: resposta de assinatura, evento desconhecido, texto estragado.
    init?(_ texto: String, recebida: Date = .now) {
        struct Evento: Decodable {
            let e: String
            let E: Double
            let s: String?
            let k: Vela?
            struct Vela: Decodable { let o, c: String }
        }
        struct Envelope: Decodable { let data: Evento }
        let dados = Data(texto.utf8)
        guard let d = (try? JSONDecoder().decode(Envelope.self, from: dados).data) ?? (try? JSONDecoder().decode(Evento.self, from: dados))
        else { return nil }
        if d.e == "serverShutdown" {
            self = .desligando
            return
        }
        // kline_1d: o é a abertura às 00:00 UTC e c o último preço, o mesmo dia que o Google usa para cripto.
        guard d.e == "kline", let par = d.s, par.hasSuffix("USDT"), let k = d.k,
              let ultimo = Double(k.c), let abertura = Double(k.o), abertura > 0
        else { return nil }
        self = .cotacao(moeda: String(par.dropLast(4)),
                        Cotacao(preco: ultimo, variacao: ultimo / abertura - 1, moeda: "USD",
                                em: Date(timeIntervalSince1970: d.E / 1000), recebida: recebida))
    }
}

// Espera antes de reconectar: 1, 2, 4… até 60 s.
func esperaReconexao(_ tentativa: Int) -> Duration {
    .seconds(min(60, 1 << min(max(tentativa, 0), 6)))
}

// Conexão que ficou de pé trazendo cotações (como no corte das 24 h) recomeça em 1 s. Queda logo de cara, ou
// conexão muda que o vigia derrubou (par que não negocia), espera cada vez mais: nada de reconectar sem parar.
func proximaTentativa(_ tentativa: Int, durou: TimeInterval, chegou: Bool) -> Int {
    chegou && durou > 60 ? 0 : tentativa + 1
}

// Junta os ticks entre duas publicações: só o último de cada ativo importa, e a tela redesenha uma vez.
struct Fila<Valor> {
    private(set) var pendentes: [String: Valor] = [:]

    // true no primeiro tick depois de esvaziar: é a hora de agendar a publicação.
    mutating func receber(_ valor: Valor, para chave: String) -> Bool {
        defer { pendentes[chave] = valor }
        return pendentes.isEmpty
    }

    mutating func esvaziar() -> [String: Valor] {
        defer { pendentes = [:] }
        return pendentes
    }
}

// Cripto em tempo real pelo stream público da Binance (sem chave): uma conexão com o kline_1d de cada moeda em USDT.
// Caiu (rede, sono do Mac, o corte de 24 h da Binance, serverShutdown)? Reconecta com espera crescente;
// enquanto isso o REST do ciclo de 10 s cobre. O URLSessionWebSocketTask responde sozinho aos pings da Binance.
@MainActor
final class StreamBinance {
    private var moedas: Set<String> = []
    private var tarefa: Task<Void, Never>?
    private var ultimaMensagem = Date.now
    private let aoReceber: @MainActor (String, Cotacao) -> Void

    init(aoReceber: @escaping @MainActor (String, Cotacao) -> Void) {
        self.aoReceber = aoReceber
    }

    // A conexão só é refeita quando a lista de moedas muda.
    func acompanhar(_ novas: Set<String>) {
        guard novas != moedas else { return }
        moedas = novas
        tarefa?.cancel()
        tarefa = novas.isEmpty ? nil : Task { await manter(novas) }
    }

    private func manter(_ moedas: Set<String>) async {
        let streams = moedas.sorted().map { $0.lowercased() + "usdt@kline_1d" }.joined(separator: "/")
        guard let url = URL(string: "wss://data-stream.binance.vision/stream?streams=" + streams) else { return }
        var tentativa = 0
        while !Task.isCancelled {
            let inicio = Date.now
            let chegou = await conectar(url)
            tentativa = proximaTentativa(tentativa, durou: Date.now.timeIntervalSince(inicio), chegou: chegou)
            try? await Task.sleep(for: esperaReconexao(tentativa))
        }
    }

    // Lê até a conexão cair, a Binance avisar que vai desligar ou ela ficar 60 s muda (morta sem erro, ex.: depois do sono).
    // true se chegou alguma cotação.
    private func conectar(_ url: URL) async -> Bool {
        let ws = URLSession.shared.webSocketTask(with: url)
        ws.resume()
        ultimaMensagem = .now
        let vigia = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if let self, Date.now.timeIntervalSince(self.ultimaMensagem) > 60 { ws.cancel(with: .goingAway, reason: nil) }
            }
        }
        defer {
            vigia.cancel()
            ws.cancel(with: .goingAway, reason: nil)
        }
        return await withTaskCancellationHandler {
            var chegou = false
            while let mensagem = try? await ws.receive() {
                ultimaMensagem = .now
                guard case .string(let texto) = mensagem, let lida = MensagemBinance(texto) else { continue }
                switch lida {
                case .cotacao(let moeda, let cotacao):
                    chegou = true
                    aoReceber(moeda, cotacao)
                case .desligando:
                    return chegou
                }
            }
            return chegou
        } onCancel: {
            ws.cancel(with: .goingAway, reason: nil)
        }
    }
}

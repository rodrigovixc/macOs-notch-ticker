import CryptoKit
import Foundation
import Security

struct Credencial: Sendable {
    let chave: String
    let segredo: String
}

// Conta da Binance, só leitura. Endpoints: https://developers.binance.com/docs/binance-spot-api-docs
enum Binance {
    // Recusa chave que pode negociar, transferir ou sacar: o app só precisa ler saldos.
    static func verificar(_ cred: Credencial) async throws {
        let p: Permissoes = try await assinado("/sapi/v1/account/apiRestrictions", "", cred)
        guard p.soLeitura else {
            throw Falha("Use uma chave só de leitura: na Binance, deixe marcado apenas “Ativar leitura”.",
                        "Use a read-only key: on Binance, leave only “Enable Reading” checked.")
        }
    }

    static func saldos(_ cred: Credencial) async throws -> [String: Double] {
        struct Conta: Decodable {
            let balances: [Saldo]
            struct Saldo: Decodable { let asset, free, locked: String }
        }
        let conta: Conta = try await assinado("/api/v3/account", "omitZeroBalances=true", cred)
        var saldos: [String: Double] = [:]
        for s in conta.balances {
            let qtd = (Double(s.free) ?? 0) + (Double(s.locked) ?? 0)
            // Simple Earn flexível aparece como "LD" + moeda (LDBTC); LDO (Lido) tem 3 letras e escapa
            let moeda = s.asset.hasPrefix("LD") && s.asset.count > 3 ? String(s.asset.dropFirst(2)) : s.asset
            if qtd > 0 { saldos[moeda, default: 0] += qtd }
        }
        return saldos
    }

    static func assinatura(_ consulta: String, segredo: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(consulta.utf8), using: SymmetricKey(data: Data(segredo.utf8)))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private struct Hora: Decodable { let serverTime: Int64 }

    private static func assinado<T: Decodable>(_ caminho: String, _ parametros: String, _ cred: Credencial) async throws -> T {
        // Usa o relógio da Binance: com o do Mac adiantado ou atrasado ela recusa o pedido (erro -1021).
        let hora: Hora = try await baixar("https://api.binance.com/api/v3/time")
        let consulta = (parametros.isEmpty ? "" : parametros + "&") + "recvWindow=10000&timestamp=\(hora.serverTime)"
        let assinatura = assinatura(consulta, segredo: cred.segredo)
        guard let url = URL(string: "https://api.binance.com\(caminho)?\(consulta)&signature=\(assinatura)") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue(cred.chave, forHTTPHeaderField: "X-MBX-APIKEY")
        return try await baixar(req)
    }
}

// Resposta do apiRestrictions: só os campos ligados (true). Lista de permitidos, não de proibidos: uma permissão
// nova da Binance (como as opções europeias ou a Portfolio Margin) é recusada até alguém conferir que só lê.
struct Permissoes: Decodable {
    let ligadas: Set<String>

    static let deLeitura: Set<String> = ["enableReading", "enableFixReadOnly"]

    var soLeitura: Bool {
        ligadas.contains("enableReading")
            && ligadas.allSatisfy { !($0.hasPrefix("enable") || $0.hasPrefix("permits")) || Self.deLeitura.contains($0) }
    }

    init(from decoder: any Decoder) throws {
        // Campo que não é true (false, número, texto, null) não liga nada.
        struct Campo: Decodable {
            let ligado: Bool
            init(from decoder: any Decoder) throws { ligado = (try? decoder.singleValueContainer().decode(Bool.self)) ?? false }
        }
        ligadas = Set(try decoder.singleValueContainer().decode([String: Campo].self).filter(\.value.ligado).keys)
    }
}

// A Secret Key fica nas Chaves do macOS (Keychain), nunca no carteira.json.
enum Chaveiro {
    private static let servico = "io.github.rodrigovixc.stocknotch.binance"

    static func salvar(_ cred: Credencial) throws {
        apagar()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servico,
            kSecAttrAccount as String: cred.chave,
            kSecValueData as String: Data(cred.segredo.utf8),
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Falha("Não consegui guardar a chave no Keychain (erro \(status)).", "Couldn't save the key to the Keychain (error \(status)).")
        }
    }

    static func ler() -> Credencial? {
        let busca: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servico,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultado: CFTypeRef?
        guard SecItemCopyMatching(busca as CFDictionary, &resultado) == errSecSuccess,
              let item = resultado as? [String: Any],
              let chave = item[kSecAttrAccount as String] as? String,
              let dados = item[kSecValueData as String] as? Data,
              let segredo = String(data: dados, encoding: .utf8)
        else { return nil }
        return Credencial(chave: chave, segredo: segredo)
    }

    static func apagar() {
        let busca: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servico]
        SecItemDelete(busca as CFDictionary)
    }
}

import Foundation
import Combine
import Security

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var accessToken: String?
    @Published private(set) var isStarting = false
    @Published private(set) var errorMessage: String?

    private let api: BookuhAPI
    private let keychain = SessionKeychain()

    init(api: BookuhAPI = BookuhAPI()) {
        self.api = api
        do {
            accessToken = try keychain.read(account: "accessToken")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start() async {
        guard !isStarting else { return }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        do {
            if let savedToken = try keychain.read(account: "accessToken") {
                accessToken = savedToken
                return
            }
            if accessToken != nil { return }

            let issuanceKey: String
            if let savedKey = try keychain.read(account: "issuanceKey") {
                guard isValidIssuanceKey(savedKey) else {
                    throw SessionStorageError.invalidData
                }
                issuanceKey = savedKey
            } else {
                issuanceKey = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                // 응답을 잃어도 같은 사용자로 재시도하도록 요청 전에 저장한다.
                try keychain.save(issuanceKey, account: "issuanceKey")
            }

            let response = try await api.issueAnonymousUser(issuanceKey: issuanceKey)
            try keychain.save(response.accessToken, account: "accessToken")
            accessToken = response.accessToken
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isValidIssuanceKey(_ value: String) -> Bool {
        (32...128).contains(value.utf8.count) && value.utf8.allSatisfy { byte in
            (65...90).contains(byte) || (97...122).contains(byte) ||
            (48...57).contains(byte) || byte == 45 || byte == 95
        }
    }
}

private struct SessionKeychain {
    private let service = "dev.bookuh.session"

    func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SessionStorageError.readFailed }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            throw SessionStorageError.invalidData
        }
        return value
    }

    func save(_ value: String, account: String) throws {
        guard !value.isEmpty else { throw SessionStorageError.invalidData }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let query = baseQuery(account: account)
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw SessionStorageError.writeFailed
            }
        } else if status != errSecSuccess {
            throw SessionStorageError.writeFailed
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private enum SessionStorageError: LocalizedError {
    case readFailed
    case writeFailed
    case invalidData

    var errorDescription: String? {
        switch self {
        case .readFailed:
            return "저장된 접속 정보를 읽지 못했어요. 아이폰을 잠금 해제한 뒤 다시 시도해 주세요."
        case .writeFailed:
            return "접속 정보를 안전하게 저장하지 못했어요. 잠시 후 다시 시도해 주세요."
        case .invalidData:
            return "저장된 접속 정보를 확인할 수 없어요. 접속 정보 점검이 필요해요."
        }
    }
}

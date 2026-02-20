import Foundation
import Contacts

final class ContactResolver: @unchecked Sendable {
    private var cache: [String: String] = [:]
    private var phoneLookup: [String: String] = [:] // normalized digits → display name
    private var emailLookup: [String: String] = [:] // lowercased email → display name
    private var hasAccess = false
    private var didBuildLookup = false

    init() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized {
            hasAccess = true
            buildLookupTable()
        }
    }

    /// Awaitable access request — call before any name resolution
    func ensureAccess() async {
        if hasAccess && didBuildLookup { return }

        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)

        if status == .notDetermined {
            do {
                let granted = try await store.requestAccess(for: .contacts)
                if granted {
                    hasAccess = true
                    buildLookupTable()
                }
            } catch {}
        } else if status == .authorized {
            hasAccess = true
            if !didBuildLookup { buildLookupTable() }
        }
    }

    func displayName(for identifier: String) -> String {
        if let cached = cache[identifier] {
            return cached
        }

        let name = lookupName(identifier: identifier) ?? formatIdentifier(identifier)
        cache[identifier] = name
        return name
    }

    // MARK: - Build full contact lookup at startup

    private func buildLookupTable() {
        guard hasAccess else { return }
        let store = CNContactStore()

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.unifyResults = true

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                guard let name = self.contactDisplayName(contact) else { return }

                // Map every phone number variant to this name
                for phone in contact.phoneNumbers {
                    let digits = phone.value.stringValue.filter { $0.isNumber }
                    if digits.count >= 7 {
                        self.phoneLookup[digits] = name
                        // Also store last 10 digits for US numbers without country code
                        if digits.count > 10 {
                            let last10 = String(digits.suffix(10))
                            self.phoneLookup[last10] = name
                        }
                    }
                }

                // Map every email to this name
                for email in contact.emailAddresses {
                    self.emailLookup[email.value.lowercased] = name
                }
            }
            didBuildLookup = true
        } catch {
            // Fall back to raw identifiers
        }
    }

    // MARK: - Lookup from pre-built maps

    private func lookupName(identifier: String) -> String? {
        // Phone number
        if identifier.contains(where: { $0.isNumber }) && !identifier.contains("@") {
            let digits = identifier.filter { $0.isNumber }
            // Try full digits, then last 10
            if let name = phoneLookup[digits] { return name }
            if digits.count > 10, let name = phoneLookup[String(digits.suffix(10))] { return name }
        }

        // Email
        if identifier.contains("@") {
            if let name = emailLookup[identifier.lowercased()] { return name }
        }

        return nil
    }

    private func contactDisplayName(_ contact: CNContact) -> String? {
        if !contact.nickname.isEmpty { return contact.nickname }
        let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private func formatIdentifier(_ id: String) -> String {
        if id.hasPrefix("+1") && id.filter({ $0.isNumber }).count == 11 {
            let digits = id.filter { $0.isNumber }
            let area = digits.dropFirst().prefix(3)
            let exchange = digits.dropFirst(4).prefix(3)
            let number = digits.dropFirst(7)
            return "+1-\(area)-\(exchange)-\(number)"
        }
        return id
    }
}

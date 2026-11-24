import Foundation
import Contacts

final class ContactResolver: @unchecked Sendable {
    private let lock = NSLock()
    private let buildLock = NSLock()
    private var cache: [String: String] = [:]
    private var phoneLookup: [String: String] = [:] // normalized digits → display name
    private var emailLookup: [String: String] = [:] // lowercased email → display name
    private var didBuildLookup = false

    init() {}

    /// Awaitable access request — call before any name resolution
    func ensureAccess() async {
        if isReady { return }

        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)

        if status == .notDetermined {
            do {
                let granted = try await store.requestAccess(for: .contacts)
                if granted {
                    setHasAccess()
                    buildLookupTable()
                }
            } catch {}
        } else if status == .authorized {
            setHasAccess()
            buildLookupTable()
        }
    }

    func displayName(for identifier: String) -> String {
        lock.lock()
        let cached = cache[identifier]
        lock.unlock()
        if let cached {
            return cached
        }

        let name = lookupName(identifier: identifier) ?? formatIdentifier(identifier)
        lock.lock()
        cache[identifier] = name
        lock.unlock()
        return name
    }

    // MARK: - Build full contact lookup at startup

    private func buildLookupTable() {
        buildLock.lock()
        defer { buildLock.unlock() }
        guard hasAccess else { return }
        lock.lock()
        let alreadyBuilt = didBuildLookup
        lock.unlock()
        guard !alreadyBuilt else { return }
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

        var newPhoneLookup: [String: String] = [:]
        var newEmailLookup: [String: String] = [:]
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                guard let name = self.contactDisplayName(contact) else { return }

                // Map every phone number variant to this name
                for phone in contact.phoneNumbers {
                    let digits = phone.value.stringValue.filter { $0.isNumber }
                    if digits.count >= 7 {
                        newPhoneLookup[digits] = name
                        // Also store last 10 digits for US numbers without country code
                        if digits.count > 10 {
                            let last10 = String(digits.suffix(10))
                            newPhoneLookup[last10] = name
                        }
                    }
                }

                // Map every email to this name
                for email in contact.emailAddresses {
                    newEmailLookup[email.value.lowercased] = name
                }
            }
            lock.lock()
            phoneLookup = newPhoneLookup
            emailLookup = newEmailLookup
            didBuildLookup = true
            lock.unlock()
        } catch {
            // Fall back to raw identifiers
        }
    }

    // MARK: - Lookup from pre-built maps

    private func lookupName(identifier: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
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

    private var hasAccess: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasAccessValue
    }

    private var hasAccessValue = false

    private var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasAccessValue && didBuildLookup
    }

    private func setHasAccess() {
        lock.lock()
        hasAccessValue = true
        lock.unlock()
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

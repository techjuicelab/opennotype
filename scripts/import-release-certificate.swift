import Foundation
import Security
import Darwin

// CI-only import: pass the P12 password in the environment, never in process arguments.
// The temporary keychain has an empty password inside a private runner directory.
// The workflow must remove it in an always() cleanup step, including on cancellation.
enum ImportFailure: Error {
    case invalidInput(String)
    case security(OSStatus, String)
}

func check(_ status: OSStatus, _ operation: String) throws {
    guard status == errSecSuccess else { throw ImportFailure.security(status, operation) }
}

func run() throws {
    let env = ProcessInfo.processInfo.environment
    guard let temporary = env["RUNNER_TEMP"],
          let destination = env["RELEASE_KEYCHAIN_PATH"],
          let p12Path = env["P12_FILE"],
          let password = env["P12_PASSWORD"], !password.isEmpty,
          let expected = env["DEVELOPER_ID_APPLICATION"],
          expected.hasPrefix("Developer ID Application: ") else {
        throw ImportFailure.invalidInput("Missing release certificate configuration")
    }
    let runner = URL(fileURLWithPath: temporary).standardizedFileURL.resolvingSymlinksInPath()
    let keychainURL = URL(fileURLWithPath: destination).standardizedFileURL
    let p12URL = URL(fileURLWithPath: p12Path).standardizedFileURL
    let parent = keychainURL.deletingLastPathComponent().resolvingSymlinksInPath()
    // Both files belong to a single private, disposable directory on the runner.
    guard parent.path.hasPrefix(runner.path + "/"),
          p12URL.deletingLastPathComponent().resolvingSymlinksInPath() == parent,
          keychainURL.lastPathComponent.hasSuffix(".keychain-db"),
          !FileManager.default.fileExists(atPath: destination) else {
        throw ImportFailure.invalidInput("Certificate and new keychain must be inside RUNNER_TEMP")
    }
    var attributes = stat()
    guard lstat(p12Path, &attributes) == 0,
          attributes.st_mode & S_IFMT == S_IFREG,
          attributes.st_mode & 0o077 == 0, attributes.st_uid == geteuid(),
          attributes.st_size > 0, attributes.st_size <= 20_000_000 else {
        throw ImportFailure.invalidInput("P12 must be a private regular file owned by this runner")
    }
    var parentAttributes = stat()
    guard lstat(parent.path, &parentAttributes) == 0,
          parentAttributes.st_mode & S_IFMT == S_IFDIR,
          parentAttributes.st_mode & 0o077 == 0, parentAttributes.st_uid == geteuid() else {
        throw ImportFailure.invalidInput("The certificate directory must be private and owned by this runner")
    }

    try check(SecKeychainSetUserInteractionAllowed(false), "disable interaction")
    var keychain: SecKeychain?
    try "".withCString { emptyPassword in
        try check(SecKeychainCreate(destination, 0, emptyPassword, false, nil, &keychain), "create keychain")
    }
    guard let keychain else { throw ImportFailure.invalidInput("Keychain creation failed") }
    var succeeded = false
    defer { if !succeeded { SecKeychainDelete(keychain) } }
    try "".withCString { emptyPassword in
        try check(SecKeychainUnlock(keychain, 0, emptyPassword, true), "unlock keychain")
    }

    var codesign: SecTrustedApplication?
    try check(SecTrustedApplicationCreateFromPath("/usr/bin/codesign", &codesign), "trust codesign")
    guard let codesign else { throw ImportFailure.invalidInput("Code signing tool is unavailable") }
    var access: SecAccess?
    try check(SecAccessCreate("OpenNoType ephemeral release signing" as CFString, [codesign] as CFArray, &access), "create access")
    guard let access else { throw ImportFailure.invalidInput("Code signing access could not be created") }
    let options: [String: Any] = [
        kSecImportExportPassphrase as String: password,
        kSecImportExportKeychain as String: keychain,
        kSecImportExportAccess as String: access
    ]
    let data = try Data(contentsOf: p12URL)
    var imported: CFArray?
    try check(SecPKCS12Import(data as CFData, options as CFDictionary, &imported), "import P12")
    guard let items = imported as? [[String: Any]], items.count == 1,
          let identityValue = items[0][kSecImportItemIdentity as String],
          CFGetTypeID(identityValue as CFTypeRef) == SecIdentityGetTypeID() else {
        throw ImportFailure.invalidInput("P12 must contain exactly one signing identity")
    }
    let identity = identityValue as! SecIdentity
    var certificate: SecCertificate?
    try check(SecIdentityCopyCertificate(identity, &certificate), "verify certificate")
    guard let certificate,
          SecCertificateCopySubjectSummary(certificate) as String? == expected else {
        throw ImportFailure.invalidInput("Imported certificate does not match DEVELOPER_ID_APPLICATION")
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination)
    succeeded = true
    print("Release signing identity imported into the temporary keychain.")
}

do {
    try run()
} catch ImportFailure.invalidInput(let message) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
} catch ImportFailure.security(let status, let operation) {
    // Never print imported items, passwords, or raw provider errors.
    FileHandle.standardError.write(Data("Certificate import failed during \(operation) (OSStatus \(status)).\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("Certificate import failed while reading a protected file.\n".utf8))
    exit(1)
}

#!/usr/bin/env swift
// A chave que assina os zips das releases (ADR-089).
//
//   swift tools/release-key.swift generate       cria a chave no Keychain e imprime a pública
//   swift tools/release-key.swift public         imprime a pública
//   swift tools/release-key.swift export         imprime a PRIVADA, para guardar no cofre
//   swift tools/release-key.swift sign <arquivo> escreve <arquivo>.sig
//
// A privada só existe no Keychain desta máquina. Perdê-la significa trocar a chave
// e fazer todo mundo instalar uma versão à mão, porque as cópias instaladas só
// aceitam a pública que levam dentro: guarde o `export` num cofre de senhas.
import CryptoKit
import Foundation

let service = "egeon-release-key"
let account = "ed25519"

func security(_ arguments: [String], input: String? = nil) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = arguments
    let out = Pipe()
    let stdin = Pipe()
    process.standardOutput = out
    process.standardError = FileHandle.nullDevice
    process.standardInput = stdin
    try! process.run()
    if let input { stdin.fileHandleForWriting.write(Data(input.utf8)) }
    try? stdin.fileHandleForWriting.close()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

func stored() -> Curve25519.Signing.PrivateKey? {
    let found = security(["find-generic-password", "-s", service, "-a", account, "-w"])
    guard found.status == 0,
          let raw = Data(base64Encoded: found.output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    return try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "generate":
    if stored() != nil { fail("já existe uma chave no Keychain; não sobrescrevo") }
    let key = Curve25519.Signing.PrivateKey()
    // Pelo stdin de `security -i`: como argumento, a chave apareceria no `ps`.
    let secret = key.rawRepresentation.base64EncodedString()
    let command = "add-generic-password -s \(service) -a \(account) -w \(secret)\n"
    guard security(["-i"], input: command).status == 0, stored() != nil else { fail("não gravei no Keychain") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    guard let key = stored() else { fail("sem chave no Keychain") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "export":
    guard let key = stored() else { fail("sem chave no Keychain") }
    print(key.rawRepresentation.base64EncodedString())
case "sign":
    guard let path = arguments.dropFirst().first else { fail("uso: sign <arquivo>") }
    guard let key = stored() else { fail("sem chave no Keychain: rode generate") }
    guard let data = FileManager.default.contents(atPath: path) else { fail("não li \(path)") }
    guard let signature = try? key.signature(for: data) else { fail("não assinei") }
    try! signature.base64EncodedString().write(toFile: path + ".sig", atomically: true, encoding: .utf8)
    print(path + ".sig")
default:
    fail("uso: generate | public | export | sign <arquivo>")
}

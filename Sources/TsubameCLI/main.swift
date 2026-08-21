import Foundation

do {
    let command = try CLICommand.parse(arguments: Array(CommandLine.arguments.dropFirst()))
    try command.run()
} catch {
    let message = "[cli] Error: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}

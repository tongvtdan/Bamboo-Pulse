import AppKit
import PulseCore

@main
struct BambooPulseApp {
    private static func hookInput(limit: Int = 131072) throws -> Data {
        var data = Data()
        while data.count <= limit,
              let part = try FileHandle.standardInput.read(upToCount: min(8192, limit + 1 - data.count)),
              !part.isEmpty { data.append(part) }
        return data
    }

    @MainActor static func main() {
        if CommandLine.arguments.dropFirst().first == "--gemini-cli-hook" {
            let args = CommandLine.arguments
            if args.count == 3, let data = try? hookInput(limit: GeminiHook.cliFrameLimit),
               let event = GeminiHook.projectCLI(data, event: args[2]) {
                GeminiHookSocket.send(event)
            }
            print("{}")
            return
        }
        if CommandLine.arguments.dropFirst().first == "--gemini-hook" {
            let args = CommandLine.arguments
            if args.count == 4,
               let data = try? hookInput(),
               let event = GeminiHook.project(data, event: args[2], workspace: args[3], home: NSHomeDirectory(),
                                              now: Date().timeIntervalSince1970 * 1000) {
                GeminiHookSocket.send(event)
            }
            print("{}")
            return
        }
        let application = NSApplication.shared
        let delegate = PulseAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

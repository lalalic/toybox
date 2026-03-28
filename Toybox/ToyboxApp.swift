import SwiftUI
import AppAgent

/// App-wide constants (not actor-isolated so they can be used anywhere)
enum ToyboxConstants {
    static let subsystem = "com.toybox.app"
}

@main
struct ToyboxApp: App {
    @State private var appModel = AppModel()
    @State private var mcpServer: MCPServer?
    @State private var agentProvider: AppAgentToolProvider?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .task {
                    startMCPServer()
                    // Auto-open first toy in living mode
                    if let toy = appModel.toyStore.toys.first(where: { $0.modelFileName != nil }) {
                        appModel.currentToy = toy
                        appModel.state = .living
                    }
                }
        }
    }

    private func startMCPServer() {
        let server = MCPServer(name: "toybox", port: 9223)
        let agent = AppAgentToolProvider()
        server.register(tools: agent.tools)
        do {
            try server.start()
            mcpServer = server
            agentProvider = agent
        } catch {
            print("MCP server failed to start: \(error)")
        }
    }
}

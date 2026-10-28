import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let podcastStudy = UTType(exportedAs: "com.jayden.podcast-study.pack", conformingTo: .json)
    static let podcastProgress = UTType(exportedAs: "com.jayden.podcast-study.progress", conformingTo: .json)
}

struct ProgressBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.podcastProgress, .json] }
    static var writableContentTypes: [UTType] { [.podcastProgress] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@main
struct PodcastStudyApp: App {
    @StateObject private var model = StudyModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
                .tint(StudyStyle.accent)
                .preferredColorScheme(.light)
                .onOpenURL { url in Task { await model.importPack(url) } }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { model.stopAudio(message: "앱을 벗어나 재생을 멈췄어요.") }
                }
        }
    }
}

enum StudyStyle {
    static let paper = Color(red: 0.96, green: 0.95, blue: 0.91)
    static let ink = Color(red: 0.15, green: 0.20, blue: 0.17)
    static let accent = Color(red: 0.22, green: 0.38, blue: 0.29)
}

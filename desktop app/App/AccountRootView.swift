#if os(macOS)
import SwiftUI

struct AccountRootView: View {
    @ObservedObject var session: CloudSession
    @State private var email = ""
    @State private var password = ""
    var body: some View {
        Group {
            if let workspace = session.workspace {
                AccountWorkspaceView(session: session, engine: workspace).id(workspace.account.id)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "book.closed.fill").font(.system(size: 48)).foregroundStyle(.blue)
                    Text("Sign in to MyNotes").font(.largeTitle.bold())
                    Text("Your notebooks on this Mac and in the cloud.").foregroundStyle(.secondary)
                    TextField("Email address", text: $email).textContentType(.emailAddress)
                    SecureField("Password", text: $password).textContentType(.password)
                    Button("Sign in") { let value = password; password = ""; Task { await session.signIn(email: email, password: value) } }.buttonStyle(.borderedProminent).disabled(email.isEmpty || password.isEmpty)
                    Button("Continue with Google") { Task { await session.google() } }
                    Link("Invitation or password recovery", destination: URL(string: session.origin + "/forgot-password") ?? URL(string: "https://mynotes.gnyanarushi.tech")!)
                    DisclosureGroup("Application server") { TextField("https://mynotes.gnyanarushi.tech", text: $session.origin).textFieldStyle(.roundedBorder) }
                    Text("Existing local notebooks can be imported after sign-in. Their original files remain on this Mac.").font(.caption).foregroundStyle(.secondary)
                    if session.busy { ProgressView() }
                    if !session.error.isEmpty { Text(session.error).foregroundStyle(.red).textSelection(.enabled) }
                }.textFieldStyle(.roundedBorder).frame(maxWidth: 390).padding(40).disabled(session.busy).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(minWidth: 640, minHeight: 480).task { await session.restore() }
    }
}
private struct AccountWorkspaceView: View {
    @ObservedObject var session: CloudSession
    @ObservedObject var engine: DesktopSyncEngine
    @State private var importing = false
    @State private var importError = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: engine.lastError.isEmpty ? "icloud" : "icloud.slash")
                VStack(alignment: .leading) { Text(engine.account.email).font(.caption); Text(engine.status).font(.caption2).foregroundStyle(.secondary) }
                if let bytes = engine.storageBytes { Text("B2 files: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                Button("Import existing local notebooks") { importing = true }
                Button("Sync now") { Task { try? await engine.synchronize() } }.disabled(engine.running)
                Button("Sign out") { Task { await session.signOut() } }
            }.padding(10).disabled(session.signingOut)
            if !engine.lastError.isEmpty { Text(engine.lastError).font(.caption).foregroundStyle(.red).textSelection(.enabled).padding(6) }
            Divider()
            LibraryView().modelContainer(engine.container).disabled(session.signingOut)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { try? await engine.synchronize() } }
        .confirmationDialog("Import local notebooks into \(engine.account.email)?", isPresented: $importing) {
            Button("Import and synchronize") { Task { do { try await engine.migrateLegacy() } catch { importError = error.localizedDescription } } }
        } message: { Text("The existing MyNotes store and Documents/Drawings files will be copied into this account. Originals are retained. Repeating this operation resumes unfinished synchronization.") }
        .alert("Import needs attention", isPresented: Binding(get: { !importError.isEmpty }, set: { if !$0 { importError = "" } })) { Button("OK") { importError = "" } } message: { Text(importError) }
        .confirmationDialog("Unsynchronized work remains", isPresented: $session.needsOfflineSignOut) {
            Button("Keep working", role: .cancel) { }
            Button("Sign out and retain pending work") { Task { await session.signOut(retainingWork: true) } }
        } message: { Text(session.error + "\nImmediate sign-out keeps the local account data for your next sign-in.") }
    }
}
#endif

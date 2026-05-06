import SwiftUI

@main
struct AnyCopyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// 菜单栏弹出内容视图
struct ContentMenuView: View {
    @EnvironmentObject var viewModel: ClipboardViewModel
    var onConfirmSelection: () -> Void = {}
    
    var body: some View {
        MainWindowView(onConfirmSelection: onConfirmSelection)
            .frame(width: 600, height: 400)
    }
}

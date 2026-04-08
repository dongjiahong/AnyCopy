import SwiftUI
import AppKit
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var clipboardViewModel = ClipboardViewModel()
    var clipboardService: ClipboardService!
    var hotkeyService: HotkeyService!
    let localServer = LocalServerService.shared
    @Published var isMenuPresented: Bool = false
    var popover: NSPopover!
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 初始化剪贴板服务
        clipboardService = ClipboardService(viewModel: clipboardViewModel)
        clipboardService.startMonitoring()
        
        // 让 ViewModel 持有 ClipboardService 引用（复制时避免重复记录）
        clipboardViewModel.clipboardService = clipboardService
        
        // 设置 Web 服务器：新条目广播给所有手机客户端
        clipboardViewModel.onNewItem = { [weak self] item in
            self?.localServer.broadcast(item)
        }
        
        // 手机发来消息 → 写入电脑剪贴板 + 添加到历史
        localServer.onReceiveText = { [weak self] text in
            guard let self = self else { return }
            let item = ClipboardItem(type: .text, textContent: text)
            self.clipboardViewModel.addItem(item)
            self.clipboardService.copyToClipboard(item)
        }
        
        // 自动启动 Web 服务器
        localServer.start()
        
        // 设置 Popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 600, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ContentMenuView().environmentObject(clipboardViewModel)
        )
        self.popover = popover
        
        // 设置状态栏图标
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = self.statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "AnyCopy")
            button.action = #selector(statusItemClicked)
        }
        
        // 初始化快捷键服务
        hotkeyService = HotkeyService { [weak self] in
            self?.togglePopover()
        }
        hotkeyService.register()
        
        // 配置开机启动
        LaunchAtLogin.configureIfNeeded()
        
        // 设置应用为 accessory 模式（不显示 Dock 图标）
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        clipboardService.stopMonitoring()
        hotkeyService.unregister()
        localServer.stop()
    }
    
    @objc func statusItemClicked() {
        togglePopover()
    }
    
    /// 切换弹出窗口显示状态
    func togglePopover() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.popover.isShown {
                self.popover.performClose(nil)
            } else {
                if let button = self.statusItem.button {
                    self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                    // 强制激活应用，确保窗口获取焦点
                    NSApp.activate(ignoringOtherApps: true)
                    // 发送通知聚焦搜索框
                    NotificationCenter.default.post(name: .showClipboardWindow, object: nil)
                }
            }
        }
    }
}

// MARK: - 通知名称
extension Notification.Name {
    static let showClipboardWindow = Notification.Name("showClipboardWindow")
    static let focusSearchField = Notification.Name("focusSearchField")
}

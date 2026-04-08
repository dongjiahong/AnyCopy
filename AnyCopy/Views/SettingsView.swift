import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

/// 设置窗口管理器
class SettingsWindowManager: ObservableObject {
    static let shared = SettingsWindowManager()
    
    private var settingsWindow: NSWindow?
    private var viewModel: ClipboardViewModel?
    
    private init() {}
    
    func setViewModel(_ viewModel: ClipboardViewModel) {
        self.viewModel = viewModel
    }
    
    func showSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        guard let viewModel = viewModel else { return }
        
        let settingsView = SettingsWindowContent()
            .environmentObject(viewModel)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.center()
        window.contentView = NSHostingView(rootView: settingsView)
        window.isReleasedWhenClosed = false
        window.level = .floating
        
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 独立窗口的设置内容视图
struct SettingsWindowContent: View {
    @EnvironmentObject var viewModel: ClipboardViewModel
    @ObservedObject var serverService = LocalServerService.shared
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("maxHistoryCount") private var maxHistoryCount: Int = 200
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // 通用设置
                    SettingsSection(title: "通用") {
                        VStack(spacing: 10) {
                            Toggle("开机时自动启动", isOn: $launchAtLogin)
                                .onChange(of: launchAtLogin) { _, newValue in
                                    LaunchAtLogin.setEnabled(newValue)
                                }
                            
                            HStack {
                                Text("历史上限")
                                Spacer()
                                Picker("", selection: $maxHistoryCount) {
                                    Text("100").tag(100)
                                    Text("200").tag(200)
                                    Text("500").tag(500)
                                    Text("1000").tag(1000)
                                }
                                .pickerStyle(.menu)
                                .frame(width: 80)
                                .onChange(of: maxHistoryCount) { _, newValue in
                                    viewModel.trimToLimit(newValue)
                                }
                            }
                        }
                    }
                    
                    // 网络共享
                    SettingsSection(title: "网络共享") {
                        VStack(spacing: 10) {
                            HStack {
                                Text("共享服务")
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { serverService.isRunning },
                                    set: { newValue in
                                        if newValue {
                                            serverService.start()
                                        } else {
                                            serverService.stop()
                                        }
                                    }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                            }
                            
                            if serverService.isRunning {
                                Divider()
                                
                                HStack {
                                    Text("本机 IP")
                                    Spacer()
                                    Text(serverService.localIPAddress)
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                                
                                HStack {
                                    Text("访问地址")
                                    Spacer()
                                    Text("http://\(serverService.localIPAddress):\(serverService.port)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                        .textSelection(.enabled)
                                }
                                
                                Divider()
                                
                                // 二维码
                                VStack(spacing: 6) {
                                    Text("手机扫码访问")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                    
                                    if let qrImage = generateQRCode(from: "http://\(serverService.localIPAddress):\(serverService.port)") {
                                        Image(nsImage: qrImage)
                                            .interpolation(.none)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 140, height: 140)
                                            .background(Color.white)
                                            .cornerRadius(8)
                                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    // 快捷键
                    SettingsSection(title: "快捷键") {
                        HStack {
                            Text("唤醒窗口")
                            Spacer()
                            Text("⇧⌘V")
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                        }
                    }
                    
                    // 数据
                    SettingsSection(title: "数据") {
                        VStack(spacing: 10) {
                            HStack {
                                Text("历史记录")
                                Spacer()
                                Text("\(viewModel.items.count) 条")
                                    .foregroundColor(.secondary)
                            }
                            
                            Button(role: .destructive) {
                                viewModel.clearAll()
                            } label: {
                                Text("清空历史记录")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.small)
                        }
                    }
                    
                    // 关于
                    HStack {
                        Text("AnyCopy")
                            .font(.system(size: 11, weight: .medium))
                        Text("v1.0.0")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
        }
        .frame(width: 320, height: 500)
    }
    
    /// 生成二维码
    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let ciImage = filter.outputImage else { return nil }
        
        // 放大二维码（默认很小）
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: scale)
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

/// 设置分组
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
    }
}

import SwiftUI

/// 主窗口视图
struct MainWindowView: View {
    @EnvironmentObject var viewModel: ClipboardViewModel
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧面板：搜索栏 + 列表 + 底部栏
            VStack(spacing: 0) {
                // 搜索栏
                SearchBarView(searchText: $viewModel.searchText, isFocused: $isSearchFocused)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                
                Divider()
                
                // 历史列表
                ClipboardListView()
                
                Divider()
                
                // 底部工具栏
                HStack {
                    // 记录数量
                    Text("\(viewModel.items.count) 条记录")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // 设置按钮 - 打开独立窗口
                    Button(action: {
                        SettingsWindowManager.shared.showSettings()
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("设置")
                    
                    // 退出按钮
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        Image(systemName: "power")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("退出应用")
                    .padding(.leading, 8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
            .frame(width: 260)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 右侧：预览面板（占满高度）
            PreviewView()
                .frame(minWidth: 320)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // 设置 ViewModel 引用
            SettingsWindowManager.shared.setViewModel(viewModel)
            
            // 窗口出现时聚焦搜索框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showClipboardWindow)) { _ in
            // 收到显示通知时聚焦搜索框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
    }
}

#Preview {
    MainWindowView()
        .environmentObject(ClipboardViewModel())
        .frame(width: 600, height: 400)
}

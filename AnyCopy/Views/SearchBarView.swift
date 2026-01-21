import SwiftUI

/// 搜索栏视图
struct SearchBarView: View {
    @Binding var searchText: String
    var isFocused: FocusState<Bool>.Binding
    
    var body: some View {
        HStack(spacing: 8) {
            // 搜索图标
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
            
            // 搜索输入框
            TextField("搜索剪贴板历史...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused(isFocused)
                .onSubmit {
                    // 回车时可以执行操作
                }
            
            // 清除按钮
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
}

#Preview {
    @FocusState var focused: Bool
    return SearchBarView(searchText: .constant(""), isFocused: $focused)
        .padding()
        .frame(width: 400)
}

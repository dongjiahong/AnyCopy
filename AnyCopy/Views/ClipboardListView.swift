import SwiftUI
import AppKit

/// 剪贴板历史列表视图
struct ClipboardListView: View {
    @EnvironmentObject var viewModel: ClipboardViewModel
    @State private var hoveredItemId: UUID?
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.filteredItems) { item in
                        ClipboardRowView(
                            item: item,
                            isSelected: viewModel.selectedItem?.id == item.id,
                            isHovered: hoveredItemId == item.id,
                            onCopy: { copyToClipboard(item) },
                            onDelete: { viewModel.deleteItem(item) },
                            onPin: { viewModel.togglePin(item) }
                        )
                        .id(item.id)
                        .onTapGesture {
                            viewModel.selectedItem = item
                        }
                        .onHover { hovering in
                            hoveredItemId = hovering ? item.id : nil
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            .onChange(of: viewModel.selectedItem) { oldValue, newValue in
                if let item = newValue {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .overlay {
            if viewModel.filteredItems.isEmpty {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !viewModel.searchText.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "无搜索结果",
                        subtitle: "尝试其他关键词"
                    )
                } else {
                    EmptyStateView(
                        icon: "doc.on.clipboard",
                        title: "剪贴板为空",
                        subtitle: "复制内容后会自动显示"
                    )
                }
            }
        }
    }
    
    private func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let data = item.imageData {
                pasteboard.setData(data, forType: .png)
            }
        }
    }
}

/// 空状态视图
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.secondary.opacity(0.6), .secondary.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 列表行视图
struct ClipboardRowView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let isHovered: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // 置顶指示器
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
                    .rotationEffect(.degrees(-45))
            }
            
            // 类型图标 - 渐变背景
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: iconGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                    .shadow(color: iconColor.opacity(0.25), radius: 3, x: 0, y: 1)
                
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // 内容区域
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Text(item.formattedTime)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            Spacer(minLength: 4)
            
            // 操作按钮 - 悬停时显示
            if isHovered || isSelected {
                HStack(spacing: 2) {
                    // 置顶按钮
                    ActionButton(
                        icon: item.isPinned ? "pin.slash.fill" : "pin.fill",
                        color: .orange
                    ) {
                        onPin()
                    }
                    
                    // 复制按钮
                    ActionButton(icon: "doc.on.doc", color: .blue) {
                        onCopy()
                    }
                    
                    // 删除按钮
                    ActionButton(icon: "trash", color: .red) {
                        onDelete()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        } else if isHovered {
            return Color.primary.opacity(0.04)
        } else if item.isPinned {
            return Color.orange.opacity(0.05)
        } else {
            return Color.clear
        }
    }
    
    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.4)
        } else if item.isPinned {
            return Color.orange.opacity(0.2)
        } else {
            return Color.clear
        }
    }
    
    private var iconName: String {
        switch item.type {
        case .text: return "doc.text.fill"
        case .image: return "photo.fill"
        }
    }
    
    private var iconColor: Color {
        switch item.type {
        case .text: return .blue
        case .image: return .green
        }
    }
    
    private var iconGradient: [Color] {
        switch item.type {
        case .text: return [Color.blue, Color.blue.opacity(0.7)]
        case .image: return [Color.green, Color.teal]
        }
    }
}

/// 操作按钮
struct ActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(color.opacity(isPressed ? 0.18 : 0.08))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isPressed = hovering
        }
    }
}

#Preview {
    ClipboardListView()
        .environmentObject(ClipboardViewModel())
        .frame(width: 260, height: 400)
}

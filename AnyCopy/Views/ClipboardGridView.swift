import SwiftUI
import AppKit

/// 卡片网格视图 - 底部横向滚动布局
struct ClipboardGridView: View {
    @EnvironmentObject var viewModel: ClipboardViewModel
    @State private var hoveredItemId: UUID?
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { index, item in
                        ClipboardCardView(
                            item: item,
                            index: index + 1,
                            isSelected: viewModel.selectedItem?.id == item.id,
                            isHovered: hoveredItemId == item.id,
                            onCopy: { copyToClipboard(item) },
                            onDelete: { viewModel.deleteItem(item) },
                            onPin: { viewModel.togglePin(item) }
                        )
                        .id(item.id)
                        .onHover { isHovered in
                            withAnimation(.easeInOut(duration: 0.1)) {
                                hoveredItemId = isHovered ? item.id : nil
                            }
                        }
                        .onTapGesture(count: 2) {
                            copyToClipboard(item)
                        }
                        .onTapGesture(count: 1) {
                            viewModel.selectedItem = item
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.selectedItem) { _, newValue in
                if let item = newValue {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .overlay {
            if viewModel.filteredItems.isEmpty {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !viewModel.searchText.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "未找到结果",
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

/// 单个卡片视图
struct ClipboardCardView: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let isHovered: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部色条区域
            HStack {
                // 类型标签
                Text(typeLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                // 时间
                Text(item.formattedTime)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(typeColor)
            
            // 内容预览区域
            VStack(spacing: 0) {
                if item.type == .image, let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
                    // 图片预览
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 100)
                        .clipped()
                } else {
                    // 文字预览
                    Text(item.preview)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                        .frame(width: 160, height: 100, alignment: .topLeading)
                        .padding(8)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            
            // 底部信息栏
            HStack {
                // 序号
                Text("\(index)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 内容信息
                Text(contentInfo)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 操作按钮 - 悬停时显示
                if isHovered || isSelected {
                    HStack(spacing: 4) {
                        // 置顶按钮
                        CardActionButton(
                            icon: item.isPinned ? "pin.slash.fill" : "pin.fill",
                            color: .orange
                        ) {
                            onPin()
                        }
                        
                        // 复制按钮
                        CardActionButton(icon: "doc.on.doc", color: .blue) {
                            onCopy()
                        }
                        
                        // 删除按钮
                        CardActionButton(icon: "trash", color: .red) {
                            onDelete()
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 180)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 8 : 4, y: 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
    
    private var typeLabel: String {
        switch item.type {
        case .text: return "文本"
        case .image: return "图片"
        }
    }
    
    private var typeColor: Color {
        switch item.type {
        case .text: return Color.green
        case .image: return Color.blue
        }
    }
    
    private var contentInfo: String {
        switch item.type {
        case .text:
            let count = item.textContent?.count ?? 0
            return "\(count) 字符"
        case .image:
            if let data = item.imageData {
                let kb = Double(data.count) / 1024.0
                if kb < 1024 {
                    return String(format: "%.1f KB", kb)
                } else {
                    return String(format: "%.2f MB", kb / 1024.0)
                }
            }
            return ""
        }
    }
    
    private var borderColor: Color {
        if isSelected {
            return Color.accentColor
        } else if isHovered {
            return Color.primary.opacity(0.2)
        } else if item.isPinned {
            return Color.orange.opacity(0.3)
        }
        return Color.clear
    }
}

/// 卡片操作按钮
struct CardActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(isPressed ? color : .secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isPressed = hovering
        }
    }
}

#Preview {
    ClipboardGridView()
        .environmentObject(ClipboardViewModel())
        .frame(width: 600, height: 200)
}

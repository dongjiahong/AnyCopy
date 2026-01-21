import SwiftUI
import AppKit

/// 预览面板视图
struct PreviewView: View {
    @EnvironmentObject var viewModel: ClipboardViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            if let item = viewModel.selectedItem {
                // 顶部信息栏
                HStack {
                    // 类型标签
                    HStack(spacing: 6) {
                        Image(systemName: item.type == .text ? "doc.text.fill" : "photo.fill")
                            .font(.system(size: 11, weight: .medium))
                        Text(item.type == .text ? "文本" : "图片")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(item.type == .text ? .blue : .green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill((item.type == .text ? Color.blue : Color.green).opacity(0.12))
                    )
                    
                    Spacer()
                    
                    // 日期和时间
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                        Text(item.fullDateTime)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                
                Divider()
                
                // 内容预览
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch item.type {
                        case .text:
                            TextPreviewView(text: item.textContent ?? "")
                        case .image:
                            ImagePreviewView(imageData: item.imageData)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            } else {
                // 空状态
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.secondary.opacity(0.1), Color.secondary.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "square.on.square.dashed")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.secondary.opacity(0.5), .secondary.opacity(0.3)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    
                    VStack(spacing: 4) {
                        Text("选择一个项目")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text("预览内容将显示在这里")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            LinearGradient(
                colors: [Color(NSColor.textBackgroundColor), Color(NSColor.textBackgroundColor).opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

/// 文字预览视图（支持 Markdown）
struct TextPreviewView: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 尝试解析 Markdown
            if let attributedString = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attributedString)
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.9))
                    .textSelection(.enabled)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // 回退到普通文本
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.9))
                    .textSelection(.enabled)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

/// 图片预览视图
struct ImagePreviewView: View {
    let imageData: Data?
    
    var body: some View {
        if let data = imageData, let nsImage = NSImage(data: data) {
            VStack(spacing: 12) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                
                // 图片信息
                HStack {
                    Label("\(Int(nsImage.size.width)) × \(Int(nsImage.size.height))", systemImage: "aspectratio")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    let sizeKB = Double(data.count) / 1024.0
                    Text(sizeKB > 1024 ? String(format: "%.1f MB", sizeKB / 1024) : String(format: "%.0f KB", sizeKB))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }
        } else {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(height: 120)
                    
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.5))
                        
                        Text("无法加载图片")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    PreviewView()
        .environmentObject(ClipboardViewModel())
        .frame(width: 400, height: 400)
}

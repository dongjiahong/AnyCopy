import Foundation

/// 剪贴板条目类型
enum ClipboardItemType: String, Codable {
    case text = "text"
    case image = "image"
}

/// 剪贴板历史条目模型
struct ClipboardItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let type: ClipboardItemType
    let textContent: String?
    let imageData: Data?
    let preview: String
    let createdAt: Date
    var isPinned: Bool  // 是否置顶
    
    init(id: UUID = UUID(), type: ClipboardItemType, textContent: String? = nil, imageData: Data? = nil, createdAt: Date = Date(), isPinned: Bool = false) {
        self.id = id
        self.type = type
        self.textContent = textContent
        self.imageData = imageData
        self.createdAt = createdAt
        self.isPinned = isPinned
        
        // 生成预览文字
        switch type {
        case .text:
            let text = textContent ?? ""
            self.preview = String(text.prefix(80)).replacingOccurrences(of: "\n", with: " ")
        case .image:
            self.preview = "[图片]"
        }
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    /// 创建置顶/取消置顶的副本
    func toggled() -> ClipboardItem {
        var copy = self
        copy.isPinned = !self.isPinned
        return copy
    }
}

// MARK: - 时间格式化扩展
extension ClipboardItem {
    var formattedTime: String {
        let now = Date()
        let interval = now.timeIntervalSince(createdAt)
        
        if interval < 60 {
            return "刚刚"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)分钟前"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)小时前"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd HH:mm"
            return formatter.string(from: createdAt)
        }
    }
    
    /// 完整日期时间
    var fullDateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: createdAt)
    }
}

import Foundation

/// 搜索服务
class SearchService {
    static let shared = SearchService()
    
    private init() {}
    
    /// 在本地数据中搜索
    func search(items: [ClipboardItem], keyword: String) -> [ClipboardItem] {
        guard !keyword.isEmpty else { return items }
        
        let lowercasedKeyword = keyword.lowercased()
        
        return items.filter { item in
            switch item.type {
            case .text:
                return item.textContent?.lowercased().contains(lowercasedKeyword) ?? false
            case .image:
                // 图片类型不参与文字搜索
                return false
            }
        }
    }
    
    /// 高亮匹配文本（返回 AttributedString 范围）
    func highlightRanges(in text: String, for keyword: String) -> [Range<String.Index>] {
        guard !keyword.isEmpty else { return [] }
        
        var ranges: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex
        
        while let range = text.range(of: keyword, options: .caseInsensitive, range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<text.endIndex
        }
        
        return ranges
    }
}

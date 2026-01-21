import Foundation
import SwiftUI
import Combine

/// 剪贴板视图模型
class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var filteredItems: [ClipboardItem] = []
    @Published var selectedItem: ClipboardItem?
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private let storageService = StorageService.shared
    private let searchService = SearchService.shared
    
    init() {
        // 监听搜索文本变化
        $searchText
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] keyword in
                self?.filterItems(keyword: keyword)
            }
            .store(in: &cancellables)
        
        // 加载历史数据
        loadItems()
    }
    
    /// 加载历史记录
    func loadItems() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loadedItems = self?.storageService.loadItems() ?? []
            DispatchQueue.main.async {
                self?.items = loadedItems
                self?.sortItems()
                self?.filterItems(keyword: self?.searchText ?? "")
                self?.isLoading = false
                
                // 默认选中第一项
                if self?.selectedItem == nil {
                    self?.selectedItem = self?.filteredItems.first
                }
            }
        }
    }
    
    /// 排序：置顶优先，然后按时间
    private func sortItems() {
        items.sort { (a, b) -> Bool in
            if a.isPinned != b.isPinned {
                return a.isPinned
            }
            return a.createdAt > b.createdAt
        }
    }
    
    /// 添加新的剪贴板条目
    func addItem(_ item: ClipboardItem) {
        // 添加到列表头部（置顶项之后）
        let firstNonPinnedIndex = items.firstIndex { !$0.isPinned } ?? 0
        items.insert(item, at: firstNonPinnedIndex)
        
        // 检查是否超过上限，自动清理非置顶的旧记录
        let maxCount = UserDefaults.standard.integer(forKey: "maxHistoryCount")
        let limit = maxCount > 0 ? maxCount : 200  // 默认200条
        trimToLimit(limit)
        
        filterItems(keyword: searchText)
        
        // 保存到数据库
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.storageService.save(item)
        }
    }
    
    /// 置顶/取消置顶
    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        
        items[index].isPinned.toggle()
        let updatedItem = items[index]
        
        // 重新排序
        sortItems()
        filterItems(keyword: searchText)
        
        // 更新选中项
        selectedItem = updatedItem
        
        // 保存到数据库
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.storageService.updatePinned(updatedItem)
        }
    }
    
    /// 裁剪历史记录到指定上限（保留置顶项）
    func trimToLimit(_ limit: Int) {
        guard limit < 10000 else { return }
        
        // 分离置顶和非置顶
        let pinnedItems = items.filter { $0.isPinned }
        var unpinnedItems = items.filter { !$0.isPinned }
        
        // 仅裁剪非置顶项
        let unpinnedLimit = max(0, limit - pinnedItems.count)
        if unpinnedItems.count > unpinnedLimit {
            let itemsToRemove = Array(unpinnedItems.suffix(unpinnedItems.count - unpinnedLimit))
            unpinnedItems = Array(unpinnedItems.prefix(unpinnedLimit))
            
            // 从数据库删除
            DispatchQueue.global(qos: .background).async { [weak self] in
                for item in itemsToRemove {
                    self?.storageService.delete(item)
                }
            }
        }
        
        items = pinnedItems + unpinnedItems
        filterItems(keyword: searchText)
    }
    
    /// 删除条目
    func deleteItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        filterItems(keyword: searchText)
        
        if selectedItem?.id == item.id {
            selectedItem = filteredItems.first
        }
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.storageService.delete(item)
        }
    }
    
    /// 清空所有历史（保留置顶项）
    func clearAll() {
        items.removeAll { !$0.isPinned }
        filterItems(keyword: searchText)
        
        if let selected = selectedItem, !items.contains(selected) {
            selectedItem = filteredItems.first
        }
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.storageService.clearAll(keepPinned: true)
        }
    }
    
    /// 过滤条目
    private func filterItems(keyword: String) {
        if keyword.isEmpty {
            filteredItems = items
        } else {
            filteredItems = searchService.search(items: items, keyword: keyword)
        }
        
        // 更新选中项
        if let selected = selectedItem, !filteredItems.contains(selected) {
            selectedItem = filteredItems.first
        }
    }
    
    /// 选择上一项
    func selectPrevious() {
        guard let current = selectedItem,
              let index = filteredItems.firstIndex(of: current),
              index > 0 else {
            return
        }
        selectedItem = filteredItems[index - 1]
    }
    
    /// 选择下一项
    func selectNext() {
        guard let current = selectedItem,
              let index = filteredItems.firstIndex(of: current),
              index < filteredItems.count - 1 else {
            if selectedItem == nil && !filteredItems.isEmpty {
                selectedItem = filteredItems.first
            }
            return
        }
        selectedItem = filteredItems[index + 1]
    }
}

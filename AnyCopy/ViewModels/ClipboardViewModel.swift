import Foundation
import SwiftUI
import Combine

/// 剪贴板视图模型
class ClipboardViewModel: ObservableObject {
    private let initialDisplayLimit = 20
    private let pageSize = 20
    private let textPreviewLimit = 400
    
    @Published var items: [ClipboardItem] = []
    @Published var filteredItems: [ClipboardItem] = []
    @Published var selectedItem: ClipboardItem? {
        didSet {
            loadSelectedItemContentIfNeeded()
        }
    }
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var selectedTextPreview: String = ""
    @Published var isSelectedTextPreviewTruncated: Bool = false
    @Published var totalItemCount: Int = 0
    
    private var cancellables = Set<AnyCancellable>()
    private let storageService = StorageService.shared
    private var searchGeneration = 0
    private var selectedPreviewGeneration = 0
    
    /// 弱引用 ClipboardService，用于正确写入粘贴板（避免重复记录）
    weak var clipboardService: ClipboardService?
    
    /// 新条目到达时的回调（供 Web 服务器推送）
    var onNewItem: ((ClipboardItem) -> Void)?
    
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
            guard let self else { return }
            let loadedItems = self.storageService.loadRecentItems(limit: self.initialDisplayLimit, includeContent: false)
            let totalCount = self.storageService.countItems()
            DispatchQueue.main.async {
                self.items = loadedItems
                self.totalItemCount = totalCount
                self.filterItems(keyword: self.searchText)
                self.isLoading = false
                
                // 默认选中第一条非置顶记录
                if self.selectedItem == nil {
                    self.selectedItem = self.defaultSelectedItem()
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
        let firstNonPinnedIndex = items.firstIndex { !$0.isPinned } ?? items.endIndex
        items.insert(item, at: firstNonPinnedIndex)
        items = Array(items.prefix(initialDisplayLimit))
        
        // 检查是否超过上限，自动清理非置顶的旧记录
        let maxCount = UserDefaults.standard.integer(forKey: "maxHistoryCount")
        let limit = maxCount > 0 ? maxCount : 200  // 默认200条
        totalItemCount += 1
        
        filterItems(keyword: searchText)
        
        // 保存到数据库
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            self.storageService.save(item)
            self.storageService.trimToLimit(limit)
            let totalCount = self.storageService.countItems()
            DispatchQueue.main.async {
                self.totalItemCount = totalCount
            }
        }
        
        // 通知 Web 服务器推送
        onNewItem?(item)
    }
    
    /// 将指定条目复制到系统粘贴板（通过 ClipboardService 确保 lastChangeCount 同步，避免产生重复记录）
    func copyItemToClipboard(_ item: ClipboardItem) {
        let fullItem = item.hasLoadedContent ? item : (storageService.loadItem(id: item.id) ?? item)
        clipboardService?.copyToClipboard(fullItem)
    }

    /// 确认当前选中项
    func confirmSelectedItem() {
        guard let selectedItem else { return }
        copyItemToClipboard(selectedItem)
    }

    /// 清空搜索并恢复默认选择
    func clearSearch() {
        searchText = ""
        filterItems(keyword: "")
        selectedItem = defaultSelectedItem()
    }

    /// 面板每次显示时从当前结果顶部重新开始选择。
    func resetSelectionToTop() {
        selectedItem = filteredItems.first
    }
    
    /// 置顶/取消置顶
    func togglePin(_ item: ClipboardItem) {
        var updatedItem = item
        updatedItem.isPinned.toggle()
        
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = updatedItem
            sortItems()
            items = Array(items.prefix(initialDisplayLimit))
        }
        
        if let index = filteredItems.firstIndex(where: { $0.id == item.id }) {
            filteredItems[index] = updatedItem
            sortFilteredItems()
        }
        
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
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            self.storageService.trimToLimit(limit)
            let loadedItems = self.storageService.loadRecentItems(limit: self.initialDisplayLimit, includeContent: false)
            let totalCount = self.storageService.countItems()
            DispatchQueue.main.async {
                self.items = loadedItems
                self.totalItemCount = totalCount
                self.filterItems(keyword: self.searchText)
            }
        }
    }
    
    /// 删除条目
    func deleteItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        filteredItems.removeAll { $0.id == item.id }
        totalItemCount = max(0, totalItemCount - 1)
        
        if selectedItem?.id == item.id {
            selectedItem = defaultSelectedItem()
        }
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            self.storageService.delete(item)
            let loadedItems = self.storageService.loadRecentItems(limit: max(self.items.count, self.initialDisplayLimit), includeContent: false)
            let totalCount = self.storageService.countItems()
            DispatchQueue.main.async {
                self.items = loadedItems
                self.totalItemCount = totalCount
                self.filterItems(keyword: self.searchText)
            }
        }
    }
    
    /// 清空所有历史（保留置顶项）
    func clearAll() {
        items.removeAll { !$0.isPinned }
        filteredItems.removeAll { !$0.isPinned }
        totalItemCount = items.count
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            self.storageService.clearAll(keepPinned: true)
            let loadedItems = self.storageService.loadRecentItems(limit: self.initialDisplayLimit, includeContent: false)
            let totalCount = self.storageService.countItems()
            DispatchQueue.main.async {
                self.items = loadedItems
                self.totalItemCount = totalCount
                self.filterItems(keyword: self.searchText)
            }
        }
    }
    
    /// 过滤条目
    private func filterItems(keyword: String) {
        searchGeneration += 1
        let generation = searchGeneration
        let normalizedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if normalizedKeyword.isEmpty {
            filteredItems = items
            if let selected = selectedItem, !filteredItems.contains(selected) {
                selectedItem = defaultSelectedItem()
            }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let results = self.storageService.search(keyword: normalizedKeyword)
            DispatchQueue.main.async {
                guard generation == self.searchGeneration else { return }
                self.filteredItems = results
                
                if let selected = self.selectedItem, !self.filteredItems.contains(selected) {
                    self.selectedItem = self.defaultSelectedItem()
                } else if self.selectedItem == nil {
                    self.selectedItem = self.defaultSelectedItem()
                }
            }
        }
    }

    func selectItem(_ item: ClipboardItem) {
        selectedItem = item
    }

    func loadMoreItemsIfNeeded(currentItem item: ClipboardItem) {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isLoadingMore,
              items.count < totalItemCount,
              let index = filteredItems.firstIndex(of: item),
              index >= max(0, filteredItems.count - 5) else {
            return
        }

        isLoadingMore = true
        let offset = items.count
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let nextItems = self.storageService.loadRecentItems(limit: self.pageSize, offset: offset, includeContent: false)
            DispatchQueue.main.async {
                let existingIds = Set(self.items.map(\.id))
                let uniqueItems = nextItems.filter { !existingIds.contains($0.id) }
                self.items.append(contentsOf: uniqueItems)
                self.filteredItems = self.items
                self.isLoadingMore = false
            }
        }
    }

    private func loadSelectedItemContentIfNeeded() {
        selectedPreviewGeneration += 1
        let generation = selectedPreviewGeneration
        selectedTextPreview = ""
        isSelectedTextPreviewTruncated = false

        guard let item = selectedItem else { return }

        if item.type == .text, let text = item.textContent {
            selectedTextPreview = String(text.prefix(textPreviewLimit))
            isSelectedTextPreviewTruncated = text.count > textPreviewLimit
            return
        }

        if item.type == .image {
            guard !item.hasLoadedContent else { return }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self, let fullItem = self.storageService.loadItem(id: item.id) else { return }
                DispatchQueue.main.async {
                    guard generation == self.selectedPreviewGeneration,
                          self.selectedItem?.id == fullItem.id else {
                        return
                    }
                    self.replaceItem(fullItem)
                    self.selectedItem = fullItem
                }
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self,
                  let preview = self.storageService.loadTextPreview(id: item.id, limit: self.textPreviewLimit) else {
                return
            }
            DispatchQueue.main.async {
                guard generation == self.selectedPreviewGeneration,
                      self.selectedItem?.id == item.id else {
                    return
                }
                self.selectedTextPreview = preview.text
                self.isSelectedTextPreviewTruncated = preview.isTruncated
            }
        }
    }

    private func replaceItem(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        }

        if let index = filteredItems.firstIndex(where: { $0.id == item.id }) {
            filteredItems[index] = item
        }
    }

    /// 默认选择第一条非置顶记录；如果当前结果只有置顶记录，则选择第一条。
    private func defaultSelectedItem() -> ClipboardItem? {
        filteredItems.first { !$0.isPinned } ?? filteredItems.first
    }

    private func sortFilteredItems() {
        filteredItems.sort { (a, b) -> Bool in
            if a.isPinned != b.isPinned {
                return a.isPinned
            }
            return a.createdAt > b.createdAt
        }
    }
    
    /// 选择上一项
    func selectPrevious() {
        guard let current = selectedItem,
              let index = filteredItems.firstIndex(of: current),
              index > 0 else {
            return
        }
        selectItem(filteredItems[index - 1])
    }
    
    /// 选择下一项
    func selectNext() {
        guard let current = selectedItem,
              let index = filteredItems.firstIndex(of: current),
              index < filteredItems.count - 1 else {
            if selectedItem == nil && !filteredItems.isEmpty {
                selectedItem = defaultSelectedItem()
            }
            return
        }
        selectItem(filteredItems[index + 1])
    }
}

private extension ClipboardItem {
    var hasLoadedContent: Bool {
        switch type {
        case .text:
            return textContent != nil
        case .image:
            return imageData != nil
        }
    }
}

import Foundation
import SQLite3

/// SQLite 数据存储服务
class StorageService {
    static let shared = StorageService()
    
    private var db: OpaquePointer?
    private let dbPath: String
    
    private init() {
        // 数据库存储在 Application Support 目录
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AnyCopy")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        dbPath = appDir.appendingPathComponent("clipboard.db").path
        openDatabase()
        createTable()
        migrateTable()
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    /// 打开数据库连接
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("无法打开数据库: \(dbPath)")
        }
    }
    
    /// 创建数据表
    private func createTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            text_content TEXT,
            image_data BLOB,
            preview TEXT NOT NULL,
            created_at REAL NOT NULL,
            is_pinned INTEGER DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_created_at ON clipboard_items(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_pinned ON clipboard_items(is_pinned DESC);
        """
        
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("创建表失败: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }
    
    /// 迁移表结构（添加 is_pinned 列）
    private func migrateTable() {
        // 检查 is_pinned 列是否存在
        let checkSql = "SELECT is_pinned FROM clipboard_items LIMIT 1"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, checkSql, -1, &stmt, nil) != SQLITE_OK {
            // 列不存在，添加它
            let alterSql = "ALTER TABLE clipboard_items ADD COLUMN is_pinned INTEGER DEFAULT 0"
            sqlite3_exec(db, alterSql, nil, nil, nil)
        }
        sqlite3_finalize(stmt)
    }
    
    /// 保存剪贴板条目
    func save(_ item: ClipboardItem) {
        let sql = """
        INSERT OR REPLACE INTO clipboard_items (id, type, text_content, image_data, preview, created_at, is_pinned)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("准备语句失败")
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, item.type.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        
        if let text = item.textContent {
            sqlite3_bind_text(stmt, 3, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        
        if let data = item.imageData {
            data.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 4, ptr.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        
        sqlite3_bind_text(stmt, 5, item.preview, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_double(stmt, 6, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 7, item.isPinned ? 1 : 0)
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            print("保存失败")
        }
    }
    
    /// 更新置顶状态
    func updatePinned(_ item: ClipboardItem) {
        let sql = "UPDATE clipboard_items SET is_pinned = ? WHERE id = ?;"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, item.isPinned ? 1 : 0)
        sqlite3_bind_text(stmt, 2, item.id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(stmt)
    }
    
    /// 加载所有剪贴板条目（置顶优先，然后按时间排序）
    func loadItems(limit: Int = 500, offset: Int = 0) -> [ClipboardItem] {
        let sql = "SELECT id, type, text_content, image_data, preview, created_at, is_pinned FROM clipboard_items ORDER BY is_pinned DESC, created_at DESC LIMIT ? OFFSET ?;"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        sqlite3_bind_int(stmt, 2, Int32(offset))
        
        var items: [ClipboardItem] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = sqlite3_column_text(stmt, 0),
                  let typeStr = sqlite3_column_text(stmt, 1),
                  let previewStr = sqlite3_column_text(stmt, 4) else {
                continue
            }
            
            let id = UUID(uuidString: String(cString: idStr)) ?? UUID()
            let type = ClipboardItemType(rawValue: String(cString: typeStr)) ?? .text
            let preview = String(cString: previewStr)
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            let isPinned = sqlite3_column_int(stmt, 6) == 1
            
            var textContent: String?
            if let textPtr = sqlite3_column_text(stmt, 2) {
                textContent = String(cString: textPtr)
            }
            
            var imageData: Data?
            if let blobPtr = sqlite3_column_blob(stmt, 3) {
                let blobSize = sqlite3_column_bytes(stmt, 3)
                imageData = Data(bytes: blobPtr, count: Int(blobSize))
            }
            
            let item = ClipboardItem(
                id: id,
                type: type,
                textContent: textContent,
                imageData: imageData,
                createdAt: createdAt,
                isPinned: isPinned
            )
            items.append(item)
        }
        
        return items
    }
    
    /// 删除指定条目
    func delete(_ item: ClipboardItem) {
        let sql = "DELETE FROM clipboard_items WHERE id = ?;"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(stmt)
    }
    
    /// 清空所有历史记录（保留置顶项）
    func clearAll(keepPinned: Bool = true) {
        let sql = keepPinned ? "DELETE FROM clipboard_items WHERE is_pinned = 0;" : "DELETE FROM clipboard_items;"
        sqlite3_exec(db, sql, nil, nil, nil)
    }
    
    /// 搜索文字内容
    func search(keyword: String) -> [ClipboardItem] {
        let sql = "SELECT id, type, text_content, image_data, preview, created_at, is_pinned FROM clipboard_items WHERE text_content LIKE ? ORDER BY is_pinned DESC, created_at DESC LIMIT 100;"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        let pattern = "%\(keyword)%"
        sqlite3_bind_text(stmt, 1, pattern, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        
        var items: [ClipboardItem] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = sqlite3_column_text(stmt, 0),
                  let typeStr = sqlite3_column_text(stmt, 1),
                  let previewStr = sqlite3_column_text(stmt, 4) else {
                continue
            }
            
            let id = UUID(uuidString: String(cString: idStr)) ?? UUID()
            let type = ClipboardItemType(rawValue: String(cString: typeStr)) ?? .text
            let preview = String(cString: previewStr)
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            let isPinned = sqlite3_column_int(stmt, 6) == 1
            
            var textContent: String?
            if let textPtr = sqlite3_column_text(stmt, 2) {
                textContent = String(cString: textPtr)
            }
            
            var imageData: Data?
            if let blobPtr = sqlite3_column_blob(stmt, 3) {
                let blobSize = sqlite3_column_bytes(stmt, 3)
                imageData = Data(bytes: blobPtr, count: Int(blobSize))
            }
            
            let item = ClipboardItem(
                id: id,
                type: type,
                textContent: textContent,
                imageData: imageData,
                createdAt: createdAt,
                isPinned: isPinned
            )
            items.append(item)
        }
        
        return items
    }
}

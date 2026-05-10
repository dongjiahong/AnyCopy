import Foundation
import SQLite3

/// SQLite 数据存储服务
class StorageService {
    static let shared = StorageService()
    
    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.anycopy.storage")
    private let searchResultLimit = 100
    
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
        createSearchIndex()
        backfillSearchIndexIfNeeded()
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

    /// 创建 FTS5 搜索索引。trigram tokenizer 支持中英文子串搜索。
    private func createSearchIndex() {
        let sql = """
        CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_items_fts
        USING fts5(id UNINDEXED, text_content, tokenize='trigram');
        """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg {
                print("创建搜索索引失败: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    /// 从主表重建搜索索引，用于首次升级和批量删除后同步。
    private func rebuildSearchIndex() {
        let sql = """
        DELETE FROM clipboard_items_fts;
        INSERT INTO clipboard_items_fts (id, text_content)
        SELECT id, text_content
        FROM clipboard_items
        WHERE type = 'text' AND text_content IS NOT NULL AND text_content != '';
        """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg {
                print("重建搜索索引失败: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    private func backfillSearchIndexIfNeeded() {
        let countSql = "SELECT COUNT(*) FROM clipboard_items_fts;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, countSql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_int(stmt, 0) == 0 else { return }

        let textCountSql = "SELECT COUNT(*) FROM clipboard_items WHERE type = 'text' AND text_content IS NOT NULL AND text_content != '';"
        var textCountStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, textCountSql, -1, &textCountStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(textCountStmt) }

        guard sqlite3_step(textCountStmt) == SQLITE_ROW, sqlite3_column_int(textCountStmt, 0) > 0 else { return }
        rebuildSearchIndex()
    }
    
    /// 保存剪贴板条目
    func save(_ item: ClipboardItem) {
        queue.sync {
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
                _ = data.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, 4, ptr.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            
            sqlite3_bind_text(stmt, 5, item.preview, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_double(stmt, 6, item.createdAt.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 7, item.isPinned ? 1 : 0)
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                print("保存失败")
                return
            }

            syncSearchIndex(for: item)
        }
    }

    private func syncSearchIndex(for item: ClipboardItem) {
        deleteSearchIndex(id: item.id.uuidString)

        guard item.type == .text, let text = item.textContent, !text.isEmpty else { return }

        let insertSql = "INSERT INTO clipboard_items_fts (id, text_content) VALUES (?, ?);"
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(insertStmt) }

        sqlite3_bind_text(insertStmt, 1, item.id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(insertStmt, 2, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(insertStmt)
    }

    private func deleteSearchIndex(id: String) {
        let deleteSql = "DELETE FROM clipboard_items_fts WHERE id = ?;"
        var deleteStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSql, -1, &deleteStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteStmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_step(deleteStmt)
        }
        sqlite3_finalize(deleteStmt)
    }
    
    /// 更新置顶状态
    func updatePinned(_ item: ClipboardItem) {
        queue.sync {
            let sql = "UPDATE clipboard_items SET is_pinned = ? WHERE id = ?;"
            
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_int(stmt, 1, item.isPinned ? 1 : 0)
            sqlite3_bind_text(stmt, 2, item.id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_step(stmt)
        }
    }
    
    /// 加载所有剪贴板条目（置顶优先，然后按时间排序）
    func loadItems(limit: Int = 500, offset: Int = 0, includeContent: Bool = true) -> [ClipboardItem] {
        queue.sync {
            let sql: String
            if includeContent {
                sql = "SELECT id, type, text_content, image_data, preview, created_at, is_pinned FROM clipboard_items ORDER BY is_pinned DESC, created_at DESC LIMIT ? OFFSET ?;"
            } else {
                sql = "SELECT id, type, NULL, NULL, preview, created_at, is_pinned FROM clipboard_items ORDER BY is_pinned DESC, created_at DESC LIMIT ? OFFSET ?;"
            }
            
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                return []
            }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_int(stmt, 1, Int32(limit))
            sqlite3_bind_int(stmt, 2, Int32(offset))
            
            return readItems(from: stmt)
        }
    }

    /// 加载最近历史，用于默认面板和 Web 历史快照。
    func loadRecentItems(limit: Int, offset: Int = 0, includeContent: Bool = true) -> [ClipboardItem] {
        loadItems(limit: limit, offset: offset, includeContent: includeContent)
    }

    func loadItem(id: UUID) -> ClipboardItem? {
        queue.sync {
            let sql = "SELECT id, type, text_content, image_data, preview, created_at, is_pinned FROM clipboard_items WHERE id = ? LIMIT 1;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return makeItem(from: stmt)
        }
    }

    func loadTextPreview(id: UUID, limit: Int) -> (text: String, isTruncated: Bool)? {
        queue.sync {
            let sql = """
            SELECT substr(text_content, 1, ?), length(text_content)
            FROM clipboard_items
            WHERE id = ? AND type = 'text'
            LIMIT 1;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(limit))
            sqlite3_bind_text(stmt, 2, id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            guard sqlite3_step(stmt) == SQLITE_ROW,
                  let textPtr = sqlite3_column_text(stmt, 0) else {
                return nil
            }

            let text = String(cString: textPtr)
            let totalLength = Int(sqlite3_column_int(stmt, 1))
            return (text, totalLength > limit)
        }
    }

    /// 历史记录总数。
    func countItems() -> Int {
        queue.sync {
            let sql = "SELECT COUNT(*) FROM clipboard_items;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }
    }
    
    /// 删除指定条目
    func delete(_ item: ClipboardItem) {
        queue.sync {
            let sql = "DELETE FROM clipboard_items WHERE id = ?;"
            
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            
            sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_step(stmt)
            let didDelete = sqlite3_changes(db) > 0
            sqlite3_finalize(stmt)
            if didDelete {
                deleteSearchIndex(id: item.id.uuidString)
            }
        }
    }
    
    /// 清空所有历史记录（保留置顶项）
    func clearAll(keepPinned: Bool = true) {
        queue.sync {
            let sql = keepPinned ? "DELETE FROM clipboard_items WHERE is_pinned = 0;" : "DELETE FROM clipboard_items;"
            sqlite3_exec(db, sql, nil, nil, nil)
            rebuildSearchIndex()
        }
    }

    /// 裁剪完整历史记录到指定上限，始终保留置顶项。
    func trimToLimit(_ limit: Int) {
        guard limit < 10000 else { return }

        queue.sync {
            let pinnedCountSql = "SELECT COUNT(*) FROM clipboard_items WHERE is_pinned = 1;"
            var countStmt: OpaquePointer?
            var pinnedCount = 0
            if sqlite3_prepare_v2(db, pinnedCountSql, -1, &countStmt, nil) == SQLITE_OK,
               sqlite3_step(countStmt) == SQLITE_ROW {
                pinnedCount = Int(sqlite3_column_int(countStmt, 0))
            }
            sqlite3_finalize(countStmt)

            let unpinnedLimit = max(0, limit - pinnedCount)
            let deleteSql = """
            DELETE FROM clipboard_items
            WHERE is_pinned = 0
              AND id NOT IN (
                SELECT id FROM clipboard_items
                WHERE is_pinned = 0
                ORDER BY created_at DESC
                LIMIT ?
              );
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, deleteSql, -1, &stmt, nil) == SQLITE_OK else { return }

            sqlite3_bind_int(stmt, 1, Int32(unpinnedLimit))
            sqlite3_step(stmt)
            let didDelete = sqlite3_changes(db) > 0
            sqlite3_finalize(stmt)
            if didDelete {
                rebuildSearchIndex()
            }
        }
    }
    
    /// 搜索文字内容
    func search(keyword: String) -> [ClipboardItem] {
        queue.sync {
            let normalizedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKeyword.isEmpty else {
                return []
            }

            if normalizedKeyword.count >= 3 {
                return searchWithFTS(keyword: normalizedKeyword, limit: searchResultLimit)
            }

            return searchWithLike(keyword: normalizedKeyword, limit: searchResultLimit)
        }
    }

    private func searchWithFTS(keyword: String, limit: Int) -> [ClipboardItem] {
        let sql = """
        SELECT c.id, c.type, NULL, NULL, c.preview, c.created_at, c.is_pinned
        FROM clipboard_items c
        JOIN clipboard_items_fts f ON f.id = c.id
        WHERE clipboard_items_fts MATCH ?
        ORDER BY c.is_pinned DESC, c.created_at DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        let escapedKeyword = keyword.replacingOccurrences(of: "\"", with: "\"\"")
        let query = "\"\(escapedKeyword)\""
        sqlite3_bind_text(stmt, 1, query, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(stmt, 2, Int32(limit))

        return readItems(from: stmt)
    }

    private func searchWithLike(keyword: String, limit: Int) -> [ClipboardItem] {
        let sql = """
        SELECT id, type, NULL, NULL, preview, created_at, is_pinned
        FROM clipboard_items
        WHERE text_content LIKE ? ESCAPE '\\'
        ORDER BY is_pinned DESC, created_at DESC
        LIMIT ?;
        """
            
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        let pattern = "%\(escapedLikePattern(keyword))%"
        sqlite3_bind_text(stmt, 1, pattern, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(stmt, 2, Int32(limit))

        return readItems(from: stmt)
    }

    private func escapedLikePattern(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func readItems(from stmt: OpaquePointer?) -> [ClipboardItem] {
        var items: [ClipboardItem] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let item = makeItem(from: stmt) else { continue }
            items.append(item)
        }

        return items
    }

    private func makeItem(from stmt: OpaquePointer?) -> ClipboardItem? {
        guard let idStr = sqlite3_column_text(stmt, 0),
              let typeStr = sqlite3_column_text(stmt, 1),
              sqlite3_column_text(stmt, 4) != nil else {
            return nil
        }

        let id = UUID(uuidString: String(cString: idStr)) ?? UUID()
        let type = ClipboardItemType(rawValue: String(cString: typeStr)) ?? .text
        let preview = String(cString: sqlite3_column_text(stmt, 4))
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

        return ClipboardItem(
            id: id,
            type: type,
            textContent: textContent,
            imageData: imageData,
            preview: preview,
            createdAt: createdAt,
            isPinned: isPinned
        )
    }
}

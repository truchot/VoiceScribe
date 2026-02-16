import Foundation
import SQLite3

// MARK: - Typed Bind Values

/// Type-safe wrapper for SQLite parameter binding.
/// Eliminates manual sqlite3_bind_* calls with positional indices.
enum SQLValue {
    case text(String)
    case double(Double)
    case float(Float)
    case int(Int32)
    case bool(Bool)
    case uuid(UUID)
    case optionalText(String?)
    case optionalDouble(Double?)
    case null
}

// MARK: - Row Reader

/// Zero-copy wrapper around a sqlite3_stmt for column reading.
/// Provides typed accessors that handle NULL checks and conversions.
struct SQLRow {
    let stmt: OpaquePointer

    func text(_ col: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: ptr)
    }

    func string(_ col: Int32, default fallback: String = "") -> String {
        text(col) ?? fallback
    }

    func double(_ col: Int32) -> Double {
        sqlite3_column_double(stmt, col)
    }

    func float(_ col: Int32) -> Float {
        Float(sqlite3_column_double(stmt, col))
    }

    func int(_ col: Int32) -> Int {
        Int(sqlite3_column_int(stmt, col))
    }

    func bool(_ col: Int32) -> Bool {
        sqlite3_column_int(stmt, col) != 0
    }

    func isNull(_ col: Int32) -> Bool {
        sqlite3_column_type(stmt, col) == SQLITE_NULL
    }

    func optionalText(_ col: Int32) -> String? {
        isNull(col) ? nil : text(col)
    }

    func optionalDouble(_ col: Int32) -> Double? {
        isNull(col) ? nil : double(col)
    }

    func uuid(_ col: Int32) -> UUID {
        UUID(uuidString: string(col)) ?? UUID()
    }

    func date(_ col: Int32) -> Date {
        Date(timeIntervalSince1970: double(col))
    }

    func optionalDate(_ col: Int32) -> Date? {
        isNull(col) ? nil : date(col)
    }
}

// MARK: - Query Helpers

private let SQLITE_TRANSIENT_VALUE = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension SessionPersistence {

    // MARK: - Execute (INSERT/UPDATE/DELETE)

    /// Execute a write statement with typed parameters. Returns true on success.
    @discardableResult
    func execute(_ sql: String, _ params: [SQLValue] = []) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("prepare")
            return false
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt: stmt!, params: params)
        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE && result != SQLITE_ROW {
            logError("step")
            return false
        }
        return true
    }

    // MARK: - Query (SELECT → [T])

    /// Execute a read statement, mapping each row through the closure.
    func query<T>(_ sql: String, _ params: [SQLValue] = [], map: (SQLRow) -> T?) -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("prepare")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt: stmt!, params: params)

        let row = SQLRow(stmt: stmt!)
        var results: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let value = map(row) {
                results.append(value)
            }
        }
        return results
    }

    // MARK: - Query Single Row

    /// Execute a read statement expecting 0 or 1 row.
    func queryOne<T>(_ sql: String, _ params: [SQLValue] = [], map: (SQLRow) -> T?) -> T? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("prepare")
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt: stmt!, params: params)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return map(SQLRow(stmt: stmt!))
    }

    // MARK: - Scalar (COUNT, SUM, etc.)

    /// Execute a query returning a single integer value.
    func scalar(_ sql: String, _ params: [SQLValue] = []) -> Int {
        queryOne(sql, params) { $0.int(0) } ?? 0
    }

    // MARK: - Private

    private func bind(stmt: OpaquePointer, params: [SQLValue]) {
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case .text(let v):
                sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT_VALUE)
            case .double(let v):
                sqlite3_bind_double(stmt, idx, v)
            case .float(let v):
                sqlite3_bind_double(stmt, idx, Double(v))
            case .int(let v):
                sqlite3_bind_int(stmt, idx, v)
            case .bool(let v):
                sqlite3_bind_int(stmt, idx, v ? 1 : 0)
            case .uuid(let v):
                sqlite3_bind_text(stmt, idx, v.uuidString, -1, SQLITE_TRANSIENT_VALUE)
            case .optionalText(let v):
                if let v { sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT_VALUE) }
                else { sqlite3_bind_null(stmt, idx) }
            case .optionalDouble(let v):
                if let v { sqlite3_bind_double(stmt, idx, v) }
                else { sqlite3_bind_null(stmt, idx) }
            case .null:
                sqlite3_bind_null(stmt, idx)
            }
        }
    }

    private func logError(_ context: String) {
        if let db {
            Log.persistence.error("SQL \(context): \(String(cString: sqlite3_errmsg(db)))")
        }
    }
}

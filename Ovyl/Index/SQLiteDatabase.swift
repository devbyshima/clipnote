import Foundation
import SQLite3

/// A thin wrapper over a SQLite connection: run statements, bind values,
/// read rows. Not thread-safe; the search index owns one inside its actor.
nonisolated final class SQLiteDatabase {
    enum Value {
        case text(String)
        case double(Double)
        case int(Int)
        case blob(Data)
        case null
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private var handle: OpaquePointer?

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            handle = nil
            throw Failure(description: "Couldn't open the search index: \(message)")
        }
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
    }

    deinit {
        sqlite3_close(handle)
    }

    private var message: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "closed"
    }

    func execute(_ sql: String, _ values: [Value] = []) throws {
        try withStatement(sql, values) { statement in
            var result = sqlite3_step(statement)
            while result == SQLITE_ROW { result = sqlite3_step(statement) }
            guard result == SQLITE_DONE else { throw Failure(description: message) }
        }
    }

    /// Runs a query and maps each row.
    func query<T>(_ sql: String, _ values: [Value] = [], row: (Row) throws -> T) throws -> [T] {
        try withStatement(sql, values) { statement in
            var rows: [T] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else { throw Failure(description: message) }
                rows.append(try row(Row(statement: statement)))
            }
            return rows
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func withStatement<T>(_ sql: String, _ values: [Value], _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Failure(description: "\(message) in \(sql)")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, transient)
            case .double(let number): sqlite3_bind_double(statement, index, number)
            case .int(let number): sqlite3_bind_int64(statement, index, Int64(number))
            case .blob(let data):
                _ = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), transient)
                }
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return try body(statement)
    }

    struct Row {
        let statement: OpaquePointer

        func text(_ column: Int32) -> String {
            sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        }

        func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }

        func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }

        func blob(_ column: Int32) -> Data {
            guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
        }
    }
}

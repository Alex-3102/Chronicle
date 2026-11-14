import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum DatabaseError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)

    public var description: String {
        switch self {
        case .open(let message): return "open: \(message)"
        case .prepare(let message): return "prepare: \(message)"
        case .step(let message): return "step: \(message)"
        }
    }
}

public enum SQLValue {
    case text(String)
    case int(Int)
    case double(Double)
    case null
}

public struct SQLRow {
    private let values: [String: SQLValue]

    init(values: [String: SQLValue]) {
        self.values = values
    }

    public func text(_ key: String) -> String? {
        guard case .text(let value)? = values[key] else { return nil }
        return value
    }

    public func double(_ key: String) -> Double? {
        guard let value = values[key] else { return nil }
        switch value {
        case .double(let number): return number
        case .int(let number): return Double(number)
        default: return nil
        }
    }

    public func int(_ key: String) -> Int? {
        guard let value = values[key] else { return nil }
        switch value {
        case .int(let number): return number
        case .double(let number): return Int(number)
        default: return nil
        }
    }
}

public final class SQLiteDatabase {
    private var handle: OpaquePointer?

    public init(path: String) throws {
        if sqlite3_open(path, &handle) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            handle = nil
            throw DatabaseError.open(message)
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    public func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &errorPointer) != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorPointer)
            throw DatabaseError.step(message)
        }
    }

    public func run(_ sql: String, _ params: [SQLValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(statement, params)
        if sqlite3_step(statement) != SQLITE_DONE {
            throw DatabaseError.step(errorMessage)
        }
    }

    public func query(_ sql: String, _ params: [SQLValue] = []) throws -> [SQLRow] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(statement, params)

        var rows: [SQLRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var values: [String: SQLValue] = [:]
            let columnCount = sqlite3_column_count(statement)
            for index in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_TEXT:
                    let text = sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
                    values[name] = .text(text)
                case SQLITE_INTEGER:
                    values[name] = .int(Int(sqlite3_column_int64(statement, index)))
                case SQLITE_FLOAT:
                    values[name] = .double(sqlite3_column_double(statement, index))
                default:
                    values[name] = .null
                }
            }
            rows.append(SQLRow(values: values))
        }
        return rows
    }

    private var errorMessage: String {
        guard let handle else { return "database is closed" }
        return String(cString: sqlite3_errmsg(handle))
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &statement, nil) != SQLITE_OK {
            throw DatabaseError.prepare(errorMessage)
        }
        guard let statement else {
            throw DatabaseError.prepare("empty statement")
        }
        return statement
    }

    private func bind(_ statement: OpaquePointer, _ params: [SQLValue]) throws {
        for (offset, value) in params.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let string):
                sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
            case .int(let number):
                sqlite3_bind_int64(statement, index, Int64(number))
            case .double(let number):
                sqlite3_bind_double(statement, index, number)
            case .null:
                sqlite3_bind_null(statement, index)
            }
        }
    }
}

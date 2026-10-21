import Foundation
struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}
func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #fileID, line: Int = #line) throws {
    if actual != expected { throw CheckFailure("\(file):\(line): \(actual) != \(expected) \(message)") }
}
func checkTrue(_ value: Bool, file: String = #fileID, line: Int = #line) throws { try checkEqual(value, true, file: file, line: line) }
func checkFalse(_ value: Bool, file: String = #fileID, line: Int = #line) throws { try checkEqual(value, false, file: file, line: line) }
func checkLessOrEqual(_ value: Int, _ limit: Int, file: String = #fileID, line: Int = #line) throws { try checkTrue(value <= limit, file: file, line: line) }
func checkThrows(_ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw CheckFailure("Expected an error")
}

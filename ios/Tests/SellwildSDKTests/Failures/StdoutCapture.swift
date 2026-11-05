import Foundation

/// What the process writes to standard output while `body` runs:
///
///     let out = try StdoutCapture.run { print("hello") }   // "hello\n"
///
/// For the SDK's two print closures (`SellwildLog` and the `SellwildFailures`
/// debug echo). Anything another thread prints meanwhile lands here too, so
/// assert with `contains`. Keep `body` short: the pipe is read afterwards.
enum StdoutCapture {

    struct Failed: Error {
        let call: String
    }

    static func run(_ body: () -> Void) throws -> String {
        let pipe = Pipe()
        fflush(stdout)
        let saved = dup(STDOUT_FILENO)
        guard saved >= 0 else { throw Failed(call: "dup") }
        guard dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO) >= 0 else {
            close(saved)
            throw Failed(call: "dup2")
        }
        body()
        fflush(stdout)
        let restored = dup2(saved, STDOUT_FILENO)
        close(saved)
        try pipe.fileHandleForWriting.close()
        guard restored >= 0 else { throw Failed(call: "dup2 restore") }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}

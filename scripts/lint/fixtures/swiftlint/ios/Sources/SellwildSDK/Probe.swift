// House-rule probe for scripts/lint/swiftlint-config.test.mjs. A line that
// must be flagged ends with "expect: <rule>"; every other line must not be.
import Foundation
import os // expect: no_os_logger

func probe(_ printer: Printer, _ logger: Sink) async {
    print("x") // expect: no_print
    debugPrint(1) // expect: no_print
    dump(1) // expect: no_print
    NSLog("z") // expect: no_print
    os_log("z") // expect: no_print
    printer.print("a method named print is fine")
    // print("in a comment")
    let text = "print(1) and catch {} in a string"
    let made = Logger(subsystem: "a", category: "b") // expect: no_os_logger
    let full = os.Logger() // expect: no_os_logger
    logger.error("bad") // expect: no_os_logger
    self.logger.fault("bad") // expect: no_os_logger
    let ours = SellwildLogger(text)
    do { try work() } catch {} // expect: empty_catch
    do { try work() } catch let err as NSError { } // expect: empty_catch
    do { try work() } catch { /* nothing */ } // expect: empty_catch_comment
    do { try work() } catch { // expect: empty_catch_comment
    }
    do { try work() } catch { // a comment with {braces}
        report(error)
    }
    do {
        try work()
    } catch {
        report(error)
    }
    // } catch {}
    /// Example: `} catch {}`
    Task { try await work() } // expect: unhandled_throwing_task
    _ = (made, full, ours)
}

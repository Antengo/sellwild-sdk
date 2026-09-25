// PRINT_EXEMPT: may print, may not swallow.
func failureEcho(_ line: String) {
    print(line)
    do { try work() } catch {} // expect: empty_catch
}

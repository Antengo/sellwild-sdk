// Tests may print (the print gate skips them) but may not swallow.
func probeTest() {
    print("tests may print")
    do { try work() } catch {} // expect: empty_catch
}

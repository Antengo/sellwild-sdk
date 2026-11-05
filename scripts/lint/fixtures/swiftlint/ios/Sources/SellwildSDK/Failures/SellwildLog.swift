// PRINT_EXEMPT: may print and use os.Logger, may not swallow.
import os

func echo(_ line: String) {
    print(line)
    Logger().info("x")
    do { try work() } catch {} // expect: empty_catch
}

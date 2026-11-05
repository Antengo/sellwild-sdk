// samples/ is linted. The print bans cover shipped SDK code only, so a
// sample may print; an empty catch still fails.
func sample() {
    print("a sample may print")
    do { try work() } catch {} // expect: empty_catch
}

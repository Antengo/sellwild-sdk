import XCTest
import UIKit
import WebKit
import JavaScriptCore
@testable import SellwildSDK

/// The audio guard's failure reporting, with nothing left running when a
/// test ends: `apply` runs with a scripted evaluator or a WKWebView that
/// answers `evaluateJavaScript` itself, and the shim's JavaScript runs in
/// JavaScriptCore on a fake page. No WebContent process is used, so no
/// evaluation can finish late and report into another test's capture.
final class SellwildAudioGuardFailureTests: FailureCapturingTestCase {

    /// A scripted `SellwildAdAudioGuard.Evaluator`: records each call and
    /// answers at once with the next scripted outcome (a zero count when the
    /// script runs out).
    private final class ScriptedEvaluator {
        private(set) var calls: [(webView: WKWebView, script: String)] = []
        var outcomes: [(Any?, Error?)] = []
        var onCall: (() -> Void)?

        var evaluate: SellwildAdAudioGuard.Evaluator {
            { [self] webView, script, done in
                calls.append((webView, script))
                let next: (Any?, Error?) = outcomes.isEmpty ? (NSNumber(value: 0), nil) : outcomes.removeFirst()
                done(next.0, next.1)
                onCall?()
            }
        }
    }

    // MARK: Pure report

    func testReportCoversEachOutcome() {
        SellwildAdAudioGuard.report(result: 0, error: nil)
        SellwildAdAudioGuard.report(result: nil, error: nil)
        SellwildAdAudioGuard.report(result: "not a count", error: nil)
        capture.none()

        SellwildAdAudioGuard.report(result: 2, error: nil)
        let caught = capture.only(.adAudioGuardException, label: .banner)
        XCTAssertEqual(caught?.attributes["msg"], "mute shim caught errors in the ad page")
        XCTAssertEqual(caught?.attributes["severity"], "warn")

        resetCapture()
        SellwildAdAudioGuard.report(result: nil, error: PlannedError())
        let event = capture.only(.adAudioGuardException, label: .banner)
        XCTAssertEqual(event?.attributes["msg"], "mute shim evaluation failed: planned test error")
        XCTAssertEqual(event?.attributes["severity"], "warn")
    }

    // MARK: apply, with a scripted evaluator

    func testApplyEvaluatesTheShimInEveryWebViewAndReportsEachResult() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 250))
        let nested = UIView()
        let first = WKWebView()
        let second = WKWebView()
        container.addSubview(nested)
        nested.addSubview(first)
        container.addSubview(second)

        let evaluator = ScriptedEvaluator()
        evaluator.outcomes = [(NSNumber(value: 0), nil), (NSNumber(value: 3), nil)]
        SellwildAdAudioGuard.apply(to: container, remoteValues: nil, delays: [0], evaluate: evaluator.evaluate)

        XCTAssertEqual(evaluator.calls.map(\.webView), [first, second])
        XCTAssertEqual(Set(evaluator.calls.map(\.script)), [SellwildAdAudioGuard.muteScript])
        XCTAssertEqual(capture.only(.adAudioGuardException, label: .banner)?.attributes["msg"],
                       "mute shim caught errors in the ad page", "only the page that caught errors is reported")
        for webView in [first, second] {
            XCTAssertEqual(webView.configuration.userContentController.userScripts.count, 1, "the per-frame script is attached")
        }

        resetCapture()
        evaluator.outcomes = [(nil, PlannedError())]
        SellwildAdAudioGuard.apply(to: second, remoteValues: nil, delays: [0], evaluate: evaluator.evaluate)
        XCTAssertEqual(capture.only(.adAudioGuardException, label: .banner)?.attributes["msg"],
                       "mute shim evaluation failed: planned test error")
        XCTAssertEqual(second.configuration.userContentController.userScripts.count, 1, "not stacked on a repeat apply")
    }

    func testDelayedRetriesRunAndStopWhenTheContainerIsGone() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 250))
        container.addSubview(WKWebView())
        let evaluator = ScriptedEvaluator()
        let retried = expectation(description: "retry")
        evaluator.onCall = { retried.fulfill() }
        SellwildAdAudioGuard.apply(to: container, remoteValues: nil, delays: [0.05], evaluate: evaluator.evaluate)
        XCTAssertTrue(evaluator.calls.isEmpty, "a delayed pass does not run at once")
        wait(for: [retried], timeout: 10)
        XCTAssertEqual(evaluator.calls.count, 1)
        evaluator.onCall = nil

        // A container released before its retry: the retry does nothing.
        weak var gone: UIView?
        let unused = ScriptedEvaluator()
        autoreleasepool {
            let short = UIView()
            short.addSubview(WKWebView())
            gone = short
            SellwildAdAudioGuard.apply(to: short, remoteValues: nil, delays: [0.05], evaluate: unused.evaluate)
        }
        XCTAssertNil(gone)
        let later = expectation(description: "after the released retry")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { later.fulfill() }
        wait(for: [later], timeout: 10)
        XCTAssertTrue(unused.calls.isEmpty)
        capture.none()
    }

    func testDisabledGuardDoesNothing() throws {
        let container = UIView()
        let webView = WKWebView()
        container.addSubview(webView)
        let evaluator = ScriptedEvaluator()
        SellwildAdAudioGuard.apply(to: container, remoteValues: try AppConfigFactory.remote(["MOBILE_AD_MUTE_AUTOPLAY": false]),
                                   delays: [0], evaluate: evaluator.evaluate)
        XCTAssertTrue(webView.configuration.userContentController.userScripts.isEmpty)
        XCTAssertTrue(evaluator.calls.isEmpty)
        XCTAssertEqual(SellwildAdAudioGuard.retryDelays, [0, 0.4, 1.2, 2.5])
        capture.none()
    }

    // MARK: The real evaluator, answered in process

    /// A WKWebView that answers `evaluateJavaScript` itself, at once. The
    /// real evaluator (`evaluateInPage`) calls WebKit's method; this override
    /// lets that path run with no WebContent process. (A real page is not
    /// used: the simulator's process freezer can suspend WebContent for a
    /// test process mid-evaluation, so no wait makes it deterministic.)
    private final class AnsweringWebView: WKWebView {
        var answer: (Any?, Error?) = (NSNumber(value: 0), nil)
        private(set) var scripts: [String] = []

        override func evaluateJavaScript(_ javaScriptString: String,
                                         completionHandler: (@MainActor (Any?, Error?) -> Void)? = nil) {
            scripts.append(javaScriptString)
            completionHandler?(answer.0, answer.1)
        }
    }

    func testTheRealEvaluatorHandsWebKitsAnswerToTheReport() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 250))
        let webView = AnsweringWebView(frame: container.bounds)
        container.addSubview(webView)

        webView.answer = (NSNumber(value: 2), nil)
        SellwildAdAudioGuard.apply(to: container, remoteValues: nil, delays: [0])
        XCTAssertEqual(webView.scripts, [SellwildAdAudioGuard.muteScript])
        XCTAssertEqual(capture.only(.adAudioGuardException, label: .banner)?.attributes["msg"],
                       "mute shim caught errors in the ad page")

        resetCapture()
        webView.answer = (nil, PlannedError())
        SellwildAdAudioGuard.evaluateInPage(webView, "1") { result, error in
            SellwildAdAudioGuard.report(result: result, error: error)
        }
        XCTAssertEqual(webView.scripts.last, "1")
        XCTAssertEqual(capture.only(.adAudioGuardException, label: .banner)?.attributes["msg"],
                       "mute shim evaluation failed: planned test error")
    }

    // MARK: The shim's JavaScript, in JavaScriptCore

    /// Just enough of a page for the shim: media elements (optionally with a
    /// `muted` setter that throws), a MutationObserver that records itself,
    /// and `document.querySelectorAll`.
    private static let fakePage = """
        var window = this;
        var media = [];
        var observers = [];
        function HTMLMediaElement() { this.attributes = {}; }
        HTMLMediaElement.prototype.play = function () { return 'played'; };
        HTMLMediaElement.prototype.setAttribute = function (name, value) { this.attributes[name] = value; };
        function addMedia(throwing) {
          var m = new HTMLMediaElement();
          if (throwing) { Object.defineProperty(m, 'muted', { set: function () { throw new Error('nope'); } }); }
          media.push(m);
          return m;
        }
        function MutationObserver(callback) { this.callback = callback; observers.push(this); }
        MutationObserver.prototype.observe = function (target, options) { this.options = options; };
        var document = { documentElement: {}, querySelectorAll: function () { return media; } };
        """

    /// A JavaScriptCore context holding the fake page, then `setup`.
    private func page(_ setup: String = "") throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, exception in
            XCTFail("page script threw: \(exception?.toString() ?? "?")")
        }
        context.evaluateScript(Self.fakePage)
        context.evaluateScript(setup)
        return context
    }

    private func run(_ script: String, in context: JSContext) -> JSValue? {
        context.evaluateScript(script)
    }

    private func shim(_ context: JSContext) -> Int32? {
        run(SellwildAdAudioGuard.muteScript, in: context)?.toInt32()
    }

    func testTheShimMutesMediaOnceInstalledAndReportsNoErrors() throws {
        let context = try page("addMedia(false);")
        XCTAssertEqual(shim(context), 0)
        XCTAssertEqual(run("[media[0].muted, media[0].volume, media[0].attributes.muted].join('|')", in: context)?.toString(), "true|0|")
        XCTAssertEqual(run("window.__swAudioGuard === true && observers.length === 1 && observers[0].options.subtree", in: context)?.toBool(), true)

        // Installed once: a second run adds no observer and no second patch.
        XCTAssertEqual(shim(context), 0)
        XCTAssertEqual(run("observers.length", in: context)?.toInt32(), 1)
        XCTAssertEqual(run("var late = addMedia(false); [late.play(), late.muted, late.volume].join('|')", in: context)?.toString(),
                       "played|true|0", "the patched play() mutes and still plays")
        XCTAssertEqual(run("observers[0].callback(); media[1].attributes.muted", in: context)?.toString(), "",
                       "the observer mutes media added later")
        XCTAssertEqual(shim(context), 0)
    }

    func testTheShimCountsEveryErrorItCatchesAndResetsTheCount() throws {
        let context = try page("addMedia(true);")
        XCTAssertEqual(shim(context), 1, "the muted setter threw in muteAll")
        XCTAssertEqual(run("window.__swAudioGuardErrors | 0", in: context)?.toInt32(), 0, "the shim resets the count it returns")

        XCTAssertEqual(run("media[0].play()", in: context)?.toString(), "played", "a failing mute does not stop play()")
        XCTAssertEqual(run("observers[0].callback(); window.__swAudioGuardErrors", in: context)?.toInt32(), 2,
                       "play() and the observer's pass each count one")
        XCTAssertEqual(shim(context), 3, "the count so far plus this run's own")
        XCTAssertEqual(shim(context), 1)
    }

    func testTheShimCountsSetupAndQueryFailures() throws {
        XCTAssertEqual(shim(try page("MutationObserver = function () { throw new Error('no observer'); };")), 1)
        XCTAssertEqual(shim(try page("document.querySelectorAll = function () { throw new Error('no query'); };")), 1)
        XCTAssertEqual(shim(try page("Object.defineProperty(window, '__swAudioGuard', { get: function () { throw new Error('guard'); } });")), 1,
                       "an error outside the inner catches is counted too")
        XCTAssertEqual(shim(try page("HTMLMediaElement = undefined;")), 0, "a page with no media API has nothing to patch")
        capture.none()
    }
}

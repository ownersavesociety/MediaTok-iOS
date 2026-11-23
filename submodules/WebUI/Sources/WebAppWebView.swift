import Foundation
import UIKit
import Display
import WebKit
import SwiftSignalKit
import TelegramCore

private let findActiveElementY = """
function getOffset(el) {
    const rect = el.getBoundingClientRect();
    return {
        left: rect.left + window.scrollX,
        top: rect.top + window.scrollY
    };
}
getOffset(document.activeElement).top;
"""

private class WeakGameScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private let f: (WKScriptMessage) -> ()
    
    init(_ f: @escaping (WKScriptMessage) -> ()) {
        self.f = f
        
        super.init()
    }
    
    func userContentController(_ controller: WKUserContentController, didReceive scriptMessage: WKScriptMessage) {
        self.f(scriptMessage)
    }
}

private class WebViewTouchGestureRecognizer: UITapGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        self.state = .began
    }
}

private func jsStringLiteral(_ value: String) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: [value], options: []), let string = String(data: data, encoding: .utf8), string.hasPrefix("["), string.hasSuffix("]") {
        return String(string.dropFirst().dropLast())
    }
    return "\"\""
}

private func eventProxySource() -> String {
    return """
    (function() {
        var TelegramWebviewProxyProto = function() {};
        TelegramWebviewProxyProto.prototype.postEvent = function(eventName, eventData) {
            window.webkit.messageHandlers.performAction.postMessage({'eventName': eventName, 'eventData': eventData});
        };
        window.TelegramWebviewProxy = new TelegramWebviewProxyProto();
    })();
    """
}

private func securedEventProxySource(trustedOrigin: String) -> String {
    return """
    (function() {
        if (window.location.origin !== \(jsStringLiteral(trustedOrigin))) {
            return;
        }
        var TelegramWebviewProxyProto = function() {};
        TelegramWebviewProxyProto.prototype.postEvent = function(eventName, eventData) {
            window.webkit.messageHandlers.performAction.postMessage({'eventName': eventName, 'eventData': eventData});
        };
        window.TelegramWebviewProxy = new TelegramWebviewProxyProto();
    })();
    """
}

private let selectionSource = "var css = '*{-webkit-touch-callout:none;} :not(input):not(textarea):not([contenteditable=\"true\"]){-webkit-user-select:none;}';"
        + " var head = document.head || document.getElementsByTagName('head')[0];"
        + " var style = document.createElement('style'); style.type = 'text/css';" +
        " style.appendChild(document.createTextNode(css)); head.appendChild(style);"

private let videoSource = """
document.addEventListener('DOMContentLoaded', () => {
function tgBrowserDisableWebkitEnterFullscreen(videoElement) {
  if (videoElement && videoElement.webkitEnterFullscreen) {
    videoElement.setAttribute('playsinline', '');
  }
}

function tgBrowserDisableFullscreenOnExistingVideos() {
  document.querySelectorAll('video').forEach(tgBrowserDisableWebkitEnterFullscreen);
}

function tgBrowserHandleMutations(mutations) {
  mutations.forEach((mutation) => {
    if (mutation.addedNodes && mutation.addedNodes.length > 0) {
      mutation.addedNodes.forEach((newNode) => {
        if (newNode.tagName === 'VIDEO') {
          tgBrowserDisableWebkitEnterFullscreen(newNode);
        }
        if (newNode.querySelectorAll) {
          newNode.querySelectorAll('video').forEach(tgBrowserDisableWebkitEnterFullscreen);
        }
      });
    }
  });
}

tgBrowserDisableFullscreenOnExistingVideos();

const _tgbrowser_observer = new MutationObserver(tgBrowserHandleMutations);

_tgbrowser_observer.observe(document.body, {
  childList: true,
  subtree: true
});

function tgBrowserDisconnectObserver() {
  _tgbrowser_observer.disconnect();
}
});
"""

final class WebAppWebView: WKWebView {
    var handleScriptMessage: (WKScriptMessage) -> Void = { _ in }
    private(set) var trustedOrigin: String?

    var customInsets: UIEdgeInsets = .zero {
        didSet {
            if self.customInsets != oldValue {
                self.setNeedsLayout()
            }
        }
    }
        
    override var safeAreaInsets: UIEdgeInsets {
        return UIEdgeInsets(top: self.customInsets.top, left: self.customInsets.left, bottom: self.customInsets.bottom, right: self.customInsets.right)
    }
    
    init(account: Account) {
        let configuration = WKWebViewConfiguration()
                
        if #available(iOS 17.0, *) {
            var uuid: UUID?
            if let current = UserDefaults.standard.object(forKey: "TelegramWebStoreUUID_\(account.id.int64)") as? String {
                uuid = UUID(uuidString: current)!
            } else {
                let mainAccountId: Int64
                if let current = UserDefaults.standard.object(forKey: "TelegramWebStoreMainAccountId") as? Int64 {
                    mainAccountId = current
                } else {
                    mainAccountId = account.id.int64
                    UserDefaults.standard.set(mainAccountId, forKey: "TelegramWebStoreMainAccountId")
                }
                
                if account.id.int64 != mainAccountId || UserDefaults.standard.bool(forKey: "mediatok.multiaccount.isolate_webstore.v1") {
                    uuid = UUID()
                    UserDefaults.standard.set(uuid!.uuidString, forKey: "TelegramWebStoreUUID_\(account.id.int64)")
                }
            }
            
            if let uuid {
                configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: uuid)
            }
        }
        
        let contentController = WKUserContentController()
                           
        var handleScriptMessageImpl: ((WKScriptMessage) -> Void)?
        contentController.add(WeakGameScriptMessageHandler { message in
            handleScriptMessageImpl?(message)
        }, name: "performAction")
        
        let selectionScript = WKUserScript(source: selectionSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        contentController.addUserScript(selectionScript)
        
        let videoScript = WKUserScript(source: videoSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(videoScript)

        // MediaTok Mini Apps Power Pack (#451–#455)
        let ud = UserDefaults.standard
        let spoofPlatform = (ud.string(forKey: "mediatok.miniapps.spoof_platform.v1") ?? "default").lowercased()
        let allowedSpoofPlatforms: Set<String> = ["ios", "android", "tdesktop", "web"]
        if allowedSpoofPlatforms.contains(spoofPlatform) {
            let safePlatLiteral = jsStringLiteral(spoofPlatform)
            let spoofJs = """
            (function(){
                try {
                    var plat = \(safePlatLiteral);
                    if (location.hash && location.hash.indexOf('tgWebAppPlatform=') !== -1) {
                        var h = location.hash.replace(/tgWebAppPlatform=[^&]+/, 'tgWebAppPlatform=' + encodeURIComponent(plat));
                        if (h !== location.hash) { history.replaceState(null, '', h); }
                    }
                    Object.defineProperty(window, '__mediatokSpoofPlatform', { value: plat, configurable: false });
                } catch(e) {}
            })();
            """
            contentController.addUserScript(WKUserScript(source: spoofJs, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        let autoclickMs = ud.integer(forKey: "mediatok.miniapps.autoclick_ms.v1")
        if autoclickMs > 0 {
            let safeMs = max(25, min(5000, autoclickMs))
            let autoJs = """
            (function(){
                if (window.__mtAutoClickInstalled) return;
                window.__mtAutoClickInstalled = true;
                var running = false, timer = null, lastTarget = null, lastX = window.innerWidth/2, lastY = window.innerHeight/2;
                document.addEventListener('touchstart', function(e){ if(e.target && e.target.id !== '__mtAutoBtn' && e.touches && e.touches[0]){ lastTarget = e.target; lastX = e.touches[0].clientX; lastY = e.touches[0].clientY; } }, true);
                document.addEventListener('pointerdown', function(e){ if(e.target && e.target.id !== '__mtAutoBtn'){ lastTarget = e.target; lastX = e.clientX; lastY = e.clientY; } }, true);
                var btn = document.createElement('button');
                btn.id = '__mtAutoBtn';
                btn.textContent = '⚡ OFF';
                btn.style.cssText = 'position:fixed;right:12px;bottom:84px;z-index:2147483647;padding:8px 12px;border-radius:18px;border:none;background:rgba(20,20,24,0.85);color:#fff;font:600 12px -apple-system,sans-serif;box-shadow:0 4px 12px rgba(0,0,0,0.4);';
                btn.onclick = function(ev){
                    ev.stopPropagation(); ev.preventDefault();
                    running = !running;
                    btn.textContent = running ? '⚡ ON (\(safeMs)ms)' : '⚡ OFF';
                    btn.style.background = running ? '#30d158' : 'rgba(20,20,24,0.85)';
                    if (timer) { clearInterval(timer); timer = null; }
                    if (running) {
                        timer = setInterval(function(){
                            var el = (lastTarget && lastTarget.isConnected) ? lastTarget : document.elementFromPoint(lastX, lastY);
                            if (el && el.id !== '__mtAutoBtn') {
                                el.dispatchEvent(new PointerEvent('pointerdown', {bubbles:true, clientX:lastX, clientY:lastY}));
                                el.dispatchEvent(new MouseEvent('click', {bubbles:true, clientX:lastX, clientY:lastY}));
                                el.dispatchEvent(new PointerEvent('pointerup', {bubbles:true, clientX:lastX, clientY:lastY}));
                            }
                        }, \(safeMs));
                    }
                };
                document.body && document.body.appendChild(btn);
            })();
            """
            contentController.addUserScript(WKUserScript(source: autoJs, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }

        if ud.bool(forKey: "mediatok.miniapps.devtools.v1") {
            let erudaJs = """
            (function(){
                if (window.__mtErudaLoaded) return;
                window.__mtErudaLoaded = true;
                var logs = [];
                var panel = document.createElement('div');
                panel.id = '__mtDevPanel';
                panel.style.cssText = 'display:none;position:fixed;left:8px;right:8px;bottom:48px;height:44vh;z-index:2147483646;background:rgba(12,12,16,0.95);color:#e5e5ea;border:1px solid rgba(255,255,255,0.18);border-radius:14px;font:11px/1.35 ui-monospace,SFMono-Regular,Menlo,monospace;box-shadow:0 8px 24px rgba(0,0,0,0.6);flex-direction:column;overflow:hidden;';
                var out = document.createElement('div');
                out.style.cssText = 'flex:1;overflow-y:auto;padding:8px;white-space:pre-wrap;word-break:break-all;';
                var bar = document.createElement('div');
                bar.style.cssText = 'display:flex;border-top:1px solid rgba(255,255,255,0.14);background:rgba(24,24,30,0.98);';
                var inp = document.createElement('input');
                inp.placeholder = 'JS eval / window.Telegram.WebApp...';
                inp.style.cssText = 'flex:1;background:transparent;color:#fff;border:none;padding:8px;font:11px ui-monospace,monospace;outline:none;';
                var runBtn = document.createElement('button');
                runBtn.textContent = 'Run';
                runBtn.style.cssText = 'background:#0a84ff;color:#fff;border:none;padding:0 12px;font:600 11px -apple-system,sans-serif;';
                function appendLine(tag, args) {
                    try {
                        var msg = Array.prototype.slice.call(args).map(function(v){
                            if (typeof v === 'object' && v !== null) { try { return JSON.stringify(v); } catch(e) { return String(v); } }
                            return String(v);
                        }).join(' ');
                        logs.push('[' + tag + '] ' + msg);
                        if (logs.length > 200) logs.shift();
                        out.textContent = logs.join('\\n');
                        out.scrollTop = out.scrollHeight;
                    } catch(e) {}
                }
                ['log','info','warn','error'].forEach(function(k){
                    var orig = console[k];
                    console[k] = function(){
                        appendLine(k.toUpperCase(), arguments);
                        if (orig) orig.apply(console, arguments);
                    };
                });
                runBtn.onclick = function(){
                    var code = inp.value;
                    if (!code) return;
                    appendLine('>', [code]);
                    try { appendLine('<', [eval(code)]); } catch(e) { appendLine('ERR', [e && e.message ? e.message : e]); }
                    inp.value = '';
                };
                bar.appendChild(inp);
                bar.appendChild(runBtn);
                panel.appendChild(out);
                panel.appendChild(bar);
                var toggle = document.createElement('button');
                toggle.id = '__mtDevToggle';
                toggle.textContent = '🛠';
                toggle.style.cssText = 'position:fixed;right:12px;bottom:42px;z-index:2147483647;width:34px;height:34px;border-radius:17px;border:none;background:rgba(20,20,24,0.88);color:#fff;font-size:15px;box-shadow:0 4px 12px rgba(0,0,0,0.4);';
                toggle.onclick = function(ev){
                    ev.stopPropagation(); ev.preventDefault();
                    var open = panel.style.display === 'flex';
                    panel.style.display = open ? 'none' : 'flex';
                    if (!open && logs.length === 0 && window.Telegram && window.Telegram.WebApp) {
                        appendLine('WEBAPP', [{platform: window.Telegram.WebApp.platform, version: window.Telegram.WebApp.version}]);
                    }
                };
                if (document.body) {
                    document.body.appendChild(panel);
                    document.body.appendChild(toggle);
                }
            })();
            """
            contentController.addUserScript(WKUserScript(source: erudaJs, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        
        configuration.userContentController = contentController
        
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = false
        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        } else {
            configuration.mediaPlaybackRequiresUserAction = false
        }
        
        super.init(frame: CGRect(), configuration: configuration)
        
        self.disablesInteractiveKeyboardGestureRecognizer = true
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.allowsLinkPreview = false
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.interactiveTransitionGestureRecognizerTest = { point -> Bool in
            return point.x > 30.0
        }
        self.allowsBackForwardNavigationGestures = false
        if #available(iOS 16.4, *) {
            self.isInspectable = true
        } 
        
        handleScriptMessageImpl = { [weak self] message in
            if let strongSelf = self {
                strongSelf.handleScriptMessage(message)
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        print()
    }
    
    var useSecuredEventProxy = true
    func bindTrustedOrigin(from url: URL) {
        guard self.trustedOrigin == nil else {
            return
        }
        guard let origin = normalizedOrigin(url: url) else {
            return
        }

        self.trustedOrigin = origin

        let eventProxyScript = WKUserScript(source: securedEventProxySource(trustedOrigin: origin), injectionTime: .atDocumentStart, forMainFrameOnly: true)
        self.configuration.userContentController.addUserScript(eventProxyScript)
    }
    
    func setupEventProxySource() {
        self.useSecuredEventProxy = false
        
        let eventProxyScript = WKUserScript(source: eventProxySource(), injectionTime: .atDocumentStart, forMainFrameOnly: true)
        self.configuration.userContentController.addUserScript(eventProxyScript)
    }

    func isTrustedMainFrameMessage(_ message: WKScriptMessage) -> Bool {
        guard message.frameInfo.isMainFrame else {
            return false
        }
        if !self.useSecuredEventProxy {
            return true
        }
        guard let trustedOrigin = self.trustedOrigin else {
            return false
        }
        guard message.frameInfo.securityOriginString == trustedOrigin else {
            return false
        }
        if let currentOrigin = self.origin, currentOrigin != trustedOrigin {
            return false
        }
        return true
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        if #available(iOS 11.0, *) {
            let webScrollView = self.subviews.compactMap { $0 as? UIScrollView }.first
            Queue.mainQueue().after(0.1, {
                let contentView = webScrollView?.subviews.first(where: { $0.interactions.count > 1 })
                guard let dragInteraction = (contentView?.interactions.compactMap { $0 as? UIDragInteraction }.first) else {
                    return
                }
                contentView?.removeInteraction(dragInteraction)
            })
            
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        }
    }
    
    func hideScrollIndicators() {
        var hiddenViews: [UIView] = []
        for view in self.scrollView.subviews.reversed() {
            let minSize = min(view.frame.width, view.frame.height)
            if minSize < 4.0 {
                view.isHidden = true
                hiddenViews.append(view)
            }
        }
        Queue.mainQueue().after(2.0) {
            for view in hiddenViews {
                view.isHidden = false
            }
        }
    }
    
    func sendEvent(name: String, data: String?) {
        if self.useSecuredEventProxy {
            guard let trustedOrigin = self.trustedOrigin, self.origin == trustedOrigin else {
                return
            }
        }
        let script = "window.TelegramGameProxy && window.TelegramGameProxy.receiveEvent && window.TelegramGameProxy.receiveEvent(\"\(name)\", \(data ?? "null"))"
        self.evaluateJavaScript(script, completionHandler: { _, _ in
        })
    }
        
    func updateMetrics(height: CGFloat, isExpanded: Bool, isStable: Bool, transition: ContainedViewLayoutTransition) {
        let viewportData = "{height:\(height), is_expanded:\(isExpanded ? "true" : "false"), is_state_stable:\(isStable ? "true" : "false")}"
        self.sendEvent(name: "viewport_changed", data: viewportData)
        
        let safeInsetsData = "{top:\(self.customInsets.top), bottom:\(self.customInsets.bottom), left:\(self.customInsets.left), right:\(self.customInsets.right)}"
        self.sendEvent(name: "safe_area_changed", data: safeInsetsData)
    }
    
    var lastTouchTimestamp: Double?
    private(set) var didTouchOnce = false
    var onFirstTouch: () -> Void = {}
    
    func scrollToActiveElement(layout: ContainerViewLayout, completion: @escaping (CGPoint) -> Void, transition: ContainedViewLayoutTransition) {
        self.evaluateJavaScript(findActiveElementY, completionHandler: { result, _ in
            if let result = result as? CGFloat {
                Queue.mainQueue().async {
                    let convertedY = result - self.scrollView.contentOffset.y
                    let viewportHeight = self.frame.height
                    if convertedY < 0.0 || (convertedY + 44.0) > viewportHeight {
                        let targetOffset: CGFloat
                        if convertedY < 0.0 {
                            targetOffset = max(0.0, result - 36.0)
                        } else {
                            targetOffset = max(0.0, result + 60.0 - viewportHeight)
                        }
                        let contentOffset = CGPoint(x: 0.0, y: targetOffset)
                        completion(contentOffset)
                        transition.animateView({
                            self.scrollView.contentOffset = contentOffset
                        })
                    }
                }
            }
        })
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        self.lastTouchTimestamp = CACurrentMediaTime()
        if result != nil && !self.didTouchOnce {
            self.didTouchOnce = true
            self.onFirstTouch()
        }
        return result
    }
    
    override var inputAccessoryView: UIView? {
        return nil
    }
    
    var origin: String? {
        guard let url = self.url else {
            return nil
        }
        return normalizedOrigin(url: url)
    }
}

extension WKFrameInfo {
    var securityOriginString: String {
        let securityOrigin = self.securityOrigin
        return normalizedOrigin(scheme: securityOrigin.protocol, host: securityOrigin.host, port: securityOrigin.port == 0 ? nil : securityOrigin.port) ?? ""
    }
}

private func normalizedOrigin(url: URL) -> String? {
    return normalizedOrigin(scheme: url.scheme, host: url.host, port: url.port)
}

private func normalizedOrigin(scheme: String?, host: String?, port: Int?) -> String? {
    guard let scheme = scheme?.lowercased(), !scheme.isEmpty, let host = host?.lowercased(), !host.isEmpty else {
        return nil
    }

    let includePort: Bool
    if let port {
        includePort = !(scheme == "http" && port == 80) && !(scheme == "https" && port == 443)
    } else {
        includePort = false
    }

    if includePort, let port {
        return "\(scheme)://\(host):\(port)"
    } else {
        return "\(scheme)://\(host)"
    }
}

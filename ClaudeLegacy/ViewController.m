//
//  ViewController.m
//  ClaudePatcher
//
//  Created by Efimov.mg on 23/2/2026.
//
#import <objc/runtime.h>
#import <SafariServices/SafariServices.h>
#import "ViewController.h"
#import "PolyfillsLoader.h"
#import "DebugConsole.h"

#import <WebKit/WebKit.h>

@interface ViewController () <WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate>

@property (nonatomic) IBOutlet WKWebView *webView;

@end

@implementation ViewController

- (void)injectDebugBridge {
    NSString *js = @"(function(){"
    "var send=function(level,args){try{"
    "var parts=[];for(var i=0;i<args.length;i++){var a=args[i];try{parts.push(typeof a==='string'?a:JSON.stringify(a));}catch(e){parts.push(String(a));}}"
    "window.webkit.messageHandlers.debugLog.postMessage(level+'\\u0001'+parts.join(' '));"
    "}catch(e){}};"
    "window.__dbgSend=send;"
    "['log','info','warn','error'].forEach(function(k){var o=console[k];console[k]=function(){send(k,arguments);return o.apply(console,arguments);};});"
    "window.addEventListener('error',function(e){send('uncaught',[((e.message||'')+' at '+(e.filename||'?')+':'+(e.lineno||'?')+':'+(e.colno||'?')+(e.error&&e.error.stack?('\\n'+e.error.stack):''))]);});"
    "window.addEventListener('unhandledrejection',function(e){var r=e.reason;send('promise',[(r&&r.stack)||String(r)]);});"
    "send('info',['[bridge] installed on '+location.href]);"

    "var lastSnap='';"
    "function snap(tag){try{"
    "if(window.top!==window)return;"
    "var b=document.body;"
    "var bg=b?getComputedStyle(b).backgroundColor:'?';"
    "var color=b?getComputedStyle(b).color:'?';"
    "var kids=b?b.children.length:-1;"
    "var text=b?(b.innerText||'').trim().length:-1;"
    "var scripts=document.scripts?document.scripts.length:-1;"
    "var root=document.getElementById('root')||document.getElementById('__next');"
    "var rootKids=root?root.children.length:-1;"
    "var rootHtml=root?root.innerHTML.length:-1;"
    "var ifr=document.querySelectorAll('iframe');"
    "var ifrSrc='';for(var j=0;j<Math.min(ifr.length,3);j++){ifrSrc+=(j?'|':'')+(ifr[j].src||ifr[j].getAttribute('src')||'?').slice(0,80);}"
    "var wp=(typeof window.__webpack_require__==='function');"
    "var subtle=!!(window.crypto&&window.crypto.subtle);"
    "var lt=(window.LegacyTranspiler&&window.LegacyTranspiler.cache)?Object.keys(window.LegacyTranspiler.cache).length:'?';"
    "var line=tag+' rs='+document.readyState+' title='+JSON.stringify(document.title||'')+' url='+location.pathname+location.search"
    "+' body.kids='+kids+' textLen='+text+' scripts='+scripts+' bg='+bg+' color='+color"
    "+' root='+(!!root)+' rootKids='+rootKids+' rootHtml='+rootHtml"
    "+' iframes='+ifr.length+' ifrSrc='+ifrSrc"
    "+' webpack='+wp+' subtle='+subtle+' ltCache='+lt+' ios='+(window.iosVersion||'?');"
    "if(line!==lastSnap){lastSnap=line;send('snap',[line]);}"
    "}catch(e){send('snap-err',[String(e)]);}}"
    "window.__dbgSnap=snap;"
    "window.__dbgDump=function(){try{"
    "var root=document.getElementById('root')||document.getElementById('__next')||document.body;"
    "var html=root?root.outerHTML:'(no root)';"
    "for(var i=0;i<html.length;i+=1500){send('dump',[('chunk '+(i/1500|0)+' ')+html.slice(i,i+1500)]);}"
    "send('info',['dump complete, length='+html.length]);"
    "}catch(e){send('error',['dump failed: '+e]);}};"
    "document.addEventListener('readystatechange',function(){snap('rs:'+document.readyState);});"
    "window.addEventListener('load',function(){snap('load');});"
    "setTimeout(function(){snap('t+500');},500);"
    "setTimeout(function(){snap('t+2s');},2000);"
    "setTimeout(function(){snap('t+5s');},5000);"
    "setInterval(function(){snap('tick');},3000);"

    "var _fetch=window.fetch;"
    "if(_fetch){window.fetch=function(){var args=arguments;var u=args[0];var url=(u&&u.url)||String(u);"
    "return _fetch.apply(this,args).then(function(r){if(!r.ok){send('fetch',[r.status+' '+url]);}return r;},function(err){send('fetch-fail',[String(err)+' '+url]);throw err;});};}"

    "function tag(t){if(!t||!t.tagName)return String(t);return t.tagName+(t.id?'#'+t.id:'')+(t.className&&typeof t.className==='string'?'.'+t.className.split(/\\s+/).slice(0,2).join('.'):'')+(t.getAttribute&&t.getAttribute('data-testid')?'[t='+t.getAttribute('data-testid')+']':'');}"
    "['touchstart','pointerdown','click','focus'].forEach(function(ev){document.addEventListener(ev,function(e){try{if(window.top!==window)return;send('touch',[ev+' '+tag(e.target)+' @'+((e.touches&&e.touches[0])||e).clientX+','+((e.touches&&e.touches[0])||e).clientY]);}catch(_){}} ,{capture:true,passive:true});});"

    "})();";
    WKUserScript *s = [[WKUserScript alloc] initWithSource:js
                                             injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                          forMainFrameOnly:NO];
    [_webView.configuration.userContentController addUserScript:s];
}

- (void) injectPatch {
    NSURL *scriptURL = [NSBundle.mainBundle URLForResource:@"patch" withExtension:@"js"];

    NSString *js = [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:nil];
    if (js) {
        WKUserScript *userScript = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
        [_webView.configuration.userContentController addUserScript:userScript];
    }
}

- (void)injectIOSVersion {
    NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
    NSString *versionString = [NSString stringWithFormat:@"%ld.%ld",
                               (long)version.majorVersion,
                               (long)version.minorVersion];

    NSString *js = [NSString stringWithFormat:
                    @"window.iosVersion = %@;",
                    [self jsStringLiteral:versionString]];

    WKUserScript *script = [[WKUserScript alloc] initWithSource:js
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                               forMainFrameOnly:YES];
    [_webView.configuration.userContentController addUserScript:script];
}

- (void) injectTranspiler {
    NSURL *scriptURL = [NSBundle.mainBundle URLForResource:@"legacy-transpiler" withExtension:@"js"];

    NSString *js = [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:nil];
    if (js) {
        WKUserScript *userScript = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
        [_webView.configuration.userContentController addUserScript:userScript];
    }
}

- (void) injectMatchMediaAddEventListener {
    if ([PolyfillsLoader isIOSVersionOrNewer:14 minor:0]) {
        return;
    }
    NSURL *scriptURL = [NSBundle.mainBundle URLForResource:@"MediaQueryList.addEventListener" withExtension:@"js"];

    NSString *js = [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:nil];

    if (js) {
        WKUserScript *userScript = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
        [_webView.configuration.userContentController addUserScript:userScript];
    }
}

- (void)injectCustomCSS {
    NSString *css = @"button[data-testid='login-with-google'] { display: none !important; }"
    "button[data-testid='login-with-google'] + p { display: none !important; }"
    "video[aria-hidden='true'][autoplay][loop] { display: none !important; }";
    NSString *js = [NSString stringWithFormat:
                    @"(function(){"
                    "var s=document.createElement('style');"
                    "s.textContent=%@;"
                    "document.head.appendChild(s);"
                    "})()", [self jsStringLiteral:css]];
    WKUserScript *script = [[WKUserScript alloc] initWithSource:js
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                               forMainFrameOnly:YES];
    [_webView.configuration.userContentController addUserScript:script];
}

- (NSString *)jsStringLiteral:(NSString *)str {
    unichar ls = 0x2028;
    unichar ps = 0x2029;
    NSString *lineSep = [NSString stringWithCharacters:&ls length:1];
    NSString *paraSep = [NSString stringWithCharacters:&ps length:1];

    NSString *escaped = [str stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    escaped = [escaped stringByReplacingOccurrencesOfString:lineSep withString:@"\\u2028"];
    escaped = [escaped stringByReplacingOccurrencesOfString:paraSep withString:@"\\u2029"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"</" withString:@"<\\/"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
        ? [UIColor colorWithRed:31/255.0 green:31/255.0 blue:30/255.0 alpha:1.0]   // #1f1f1e
        : [UIColor colorWithRed:0xF8/255.0 green:0xF7/255.0 blue:0xF3/255.0 alpha:1.0];  // #F8F7F3
    }];

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    _webView.scrollView.refreshControl = refreshControl;

    _webView.opaque = NO;
    _webView.backgroundColor = UIColor.clearColor;
    _webView.navigationDelegate = self;
    _webView.UIDelegate = self;
    _webView.scrollView.scrollEnabled = YES;
    _webView.allowsBackForwardNavigationGestures = YES;

    [self.webView.configuration.userContentController addScriptMessageHandler:self name:@"patchScript"];
    [self.webView.configuration.userContentController addScriptMessageHandler:self name:@"debugLog"];
    [self injectDebugBridge];

    [self injectIOSVersion];
    [self injectCustomCSS];
    [self injectTranspiler];
    [self injectPatch];
    [PolyfillsLoader injectPolyfillsIntoController:_webView.configuration.userContentController];
    [self injectMatchMediaAddEventListener];

    __weak WKWebView *weakWeb = _webView;
    [[DebugConsole shared] setDumpHandler:^{
        [weakWeb evaluateJavaScript:@"typeof __dbgDump==='function'?__dbgDump():'no-dump'" completionHandler:nil];
    }];

    [[DebugConsole shared] append:@"loading https://claude.ai" level:@"info"];
    [_webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://claude.ai"]]];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

- (void)handleRefresh:(UIRefreshControl *)refreshControl {
    [_webView reload];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [webView.scrollView.refreshControl endRefreshing];
    [[DebugConsole shared] append:[NSString stringWithFormat:@"finish: %@", webView.URL.absoluteString] level:@"info"];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [webView.scrollView.refreshControl endRefreshing];
    [[DebugConsole shared] append:[NSString stringWithFormat:@"nav fail: %@", error.localizedDescription] level:@"nav-fail"];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [webView.scrollView.refreshControl endRefreshing];
    [[DebugConsole shared] append:[NSString stringWithFormat:@"provisional fail: %@ (%@)", error.localizedDescription, error.userInfo[NSURLErrorFailingURLStringErrorKey] ?: @"?"] level:@"nav-fail"];
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [[DebugConsole shared] append:[NSString stringWithFormat:@"start: %@", webView.URL.absoluteString] level:@"info"];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [[DebugConsole shared] append:@"web content process terminated" level:@"error"];
}

- (BOOL)isClaudeHost:(NSString *)host {
    if (!host) return NO;
    return [host isEqualToString:@"claude.ai"]
        || [host hasSuffix:@".claude.ai"]
        || [host isEqualToString:@"anthropic.com"]
        || [host hasSuffix:@".anthropic.com"];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    NSString *scheme = url.scheme.lowercaseString;

    if ([scheme isEqualToString:@"tel"] || [scheme isEqualToString:@"mailto"] || [scheme isEqualToString:@"sms"] || [scheme isEqualToString:@"facetime"]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    NSURL *url = navigationAction.request.URL;
    NSString *scheme = url.scheme.lowercaseString;

    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
        return nil;
    }

    if ([self isClaudeHost:url.host]) {
        [webView loadRequest:navigationAction.request];
        return nil;
    }

    SFSafariViewController *sfvc = [[SFSafariViewController alloc] initWithURL:url];
    sfvc.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:sfvc animated:YES completion:nil];
    return nil;
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message
{
    if ([message.name isEqualToString:@"debugLog"]) {
        if (![message.body isKindOfClass:[NSString class]]) return;
        NSString *body = message.body;
        NSRange sep = [body rangeOfString:@"\x01"];
        NSString *level = sep.location == NSNotFound ? @"log" : [body substringToIndex:sep.location];
        NSString *text = sep.location == NSNotFound ? body : [body substringFromIndex:sep.location + 1];
        [[DebugConsole shared] append:text level:level];
        return;
    }
    if (![message.name isEqualToString:@"patchScript"]) {
        return;
    }
    if (![message.body isKindOfClass:[NSString class]]) {
        NSLog(@"[patchScript]: rejected non-string message body");
        return;
    }

    NSString *code = message.body;
    NSString *wrapped = [NSString stringWithFormat:@"%@\n;'ok'", code];

    [self.webView evaluateJavaScript:wrapped completionHandler:^(id res, NSError *err) {
        if (err) {
            NSLog(@"[evaluateJavaScript]: fail (%lu chars): %@", (unsigned long)code.length, err.localizedDescription);
            [[DebugConsole shared] append:[NSString stringWithFormat:@"eval fail (%lu chars): %@", (unsigned long)code.length, err.localizedDescription] level:@"error"];
        } else {
            NSLog(@"[evaluateJavaScript]: success");
        }
    }];
}

@end

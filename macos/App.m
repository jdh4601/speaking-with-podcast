#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
@interface AppDelegate : NSObject <NSApplicationDelegate,WKNavigationDelegate,WKUIDelegate>
@property NSWindow *window;
@property WKWebView *web;
@property NSTask *backend;
@end
@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)note {
 NSMenu *bar=[NSMenu new];NSMenuItem *root=[NSMenuItem new];[bar addItem:root];NSMenu *menu=[NSMenu new];[menu addItemWithTitle:@"English Routine 정보" action:@selector(showAbout:) keyEquivalent:@""];[menu addItem:NSMenuItem.separatorItem];[menu addItemWithTitle:@"English Routine 가리기" action:@selector(hide:) keyEquivalent:@"h"];[menu addItemWithTitle:@"English Routine 종료" action:@selector(terminate:) keyEquivalent:@"q"];root.submenu=menu;
 NSMenuItem *editRoot=[[NSMenuItem alloc]initWithTitle:@"편집" action:nil keyEquivalent:@""];NSMenu *edit=[[NSMenu alloc]initWithTitle:@"편집"];NSArray *items=@[@[@"실행 취소",@"undo:",@"z"],@[@"잘라내기",@"cut:",@"x"],@[@"복사",@"copy:",@"c"],@[@"붙여넣기",@"paste:",@"v"],@[@"전체 선택",@"selectAll:",@"a"]];for(NSArray *item in items)[edit addItemWithTitle:item[0] action:NSSelectorFromString(item[1]) keyEquivalent:item[2]];editRoot.submenu=edit;[bar addItem:editRoot];NSMenuItem *vr=[[NSMenuItem alloc]initWithTitle:@"보기" action:nil keyEquivalent:@""];NSMenu *vm=[[NSMenu alloc]initWithTitle:@"보기"];NSMenuItem *reload=[vm addItemWithTitle:@"새로고침" action:@selector(reloadPage:) keyEquivalent:@"r"];reload.target=self;vr.submenu=vm;[bar addItem:vr];NSApp.mainMenu=bar;
 WKWebViewConfiguration *config=[WKWebViewConfiguration new];config.websiteDataStore=WKWebsiteDataStore.defaultDataStore;config.mediaTypesRequiringUserActionForPlayback=WKAudiovisualMediaTypeNone;self.web=[[WKWebView alloc]initWithFrame:NSZeroRect configuration:config];self.web.navigationDelegate=self;self.web.UIDelegate=self;
 self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,1240,790) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];self.window.title=@"English Routine";self.window.minSize=NSMakeSize(860,640);[self.window setFrameAutosaveName:@"EnglishRoutineWindow"];self.window.contentView=self.web;[self.window center];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
 [self.web loadHTMLString:@"<body style='background:#f3f4f0;font:16px -apple-system;color:#365e46;display:grid;place-content:center;height:90vh'>English Routine 시작 중…</body>" baseURL:nil];[self startBackend];
}
- (void)startBackend {
 NSURL *res=NSBundle.mainBundle.resourceURL;NSTask *p=[NSTask new];p.executableURL=[NSURL fileURLWithPath:@"/opt/homebrew/bin/python3"];p.arguments=@[[res URLByAppendingPathComponent:@"server.py"].path];p.currentDirectoryURL=res;NSMutableDictionary *env=[NSProcessInfo.processInfo.environment mutableCopy];env[@"PATH"]=@"/Users/jayden/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";p.environment=env;NSPipe *out=NSPipe.pipe;p.standardOutput=out;p.standardError=NSPipe.pipe;self.backend=p;__weak AppDelegate *weakSelf=self;
 out.fileHandleForReading.readabilityHandler=^(NSFileHandle *h){NSData *d=h.availableData;if(!d.length)return;NSString *s=[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding];if([s containsString:@"READY"]){dispatch_async(dispatch_get_main_queue(),^{[weakSelf.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:47831"]]];});}};
 p.terminationHandler=^(NSTask *task){dispatch_async(dispatch_get_main_queue(),^{if(NSApp.running)[weakSelf showError:@"학습 엔진이 종료되었습니다. 앱을 종료한 뒤 다시 열어주세요. 같은 앱이 이미 실행 중인지 확인하세요."];});};NSError *error=nil;if(![p launchAndReturnError:&error])[self showError:error.localizedDescription];
}
- (void)showError:(NSString *)message {NSAlert *a=[NSAlert new];a.messageText=@"English Routine";a.informativeText=message;[a runModal];}
- (void)showAbout:(id)sender {[self showError:@"8주 영어 루틴 · 팟캐스트 회화 학습\n학습 기록은 이 Mac에 저장됩니다.\n표현 추출: 로그인된 Codex CLI\n자막: 공개 YouTube 영어 자막"];}
- (void)reloadPage:(id)sender {[self.web reload];}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {[self.window makeKeyAndOrderFront:nil];return YES;}
- (void)applicationWillTerminate:(NSNotification *)note {self.backend.terminationHandler=nil;[self.backend terminate];}
- (void)webView:(WKWebView *)view decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))reply {NSURL *u=action.request.URL;if([u.scheme isEqual:@"about"]||([u.host isEqual:@"127.0.0.1"]&&u.port.intValue==47831)){reply(WKNavigationActionPolicyAllow);}else{if([@[@"https",@"http"] containsObject:u.scheme])[NSWorkspace.sharedWorkspace openURL:u];reply(WKNavigationActionPolicyCancel);}}
- (WKWebView *)webView:(WKWebView *)view createWebViewWithConfiguration:(WKWebViewConfiguration *)config forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {NSURL *u=action.request.URL;if([@[@"http",@"https"] containsObject:u.scheme])[NSWorkspace.sharedWorkspace openURL:u];return nil;}
@end
int main(int argc,const char *argv[]){@autoreleasepool{NSApplication *app=NSApplication.sharedApplication;AppDelegate *delegate=[AppDelegate new];[app setActivationPolicy:NSApplicationActivationPolicyRegular];app.delegate=delegate;[app run];}return 0;}

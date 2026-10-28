#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
@interface AppDelegate : NSObject <NSApplicationDelegate,WKNavigationDelegate,WKUIDelegate,WKScriptMessageHandler>
@property NSWindow *window;
@property WKWebView *web;
@property NSTask *backend;
@property NSURL *serverURL;
@property NSMutableData *startupOutput;
@property BOOL startupFinished;
@property BOOL stopping;
@property NSString *backendLogPath;
@end
@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)note {
 NSMenu *bar=[NSMenu new];NSMenuItem *root=[NSMenuItem new];[bar addItem:root];NSMenu *menu=[NSMenu new];[menu addItemWithTitle:@"English Routine 정보" action:@selector(showAbout:) keyEquivalent:@""];[menu addItem:NSMenuItem.separatorItem];[menu addItemWithTitle:@"English Routine 가리기" action:@selector(hide:) keyEquivalent:@"h"];[menu addItemWithTitle:@"English Routine 종료" action:@selector(terminate:) keyEquivalent:@"q"];root.submenu=menu;
 NSMenuItem *editRoot=[[NSMenuItem alloc]initWithTitle:@"편집" action:nil keyEquivalent:@""];NSMenu *edit=[[NSMenu alloc]initWithTitle:@"편집"];NSArray *items=@[@[@"실행 취소",@"undo:",@"z"],@[@"잘라내기",@"cut:",@"x"],@[@"복사",@"copy:",@"c"],@[@"붙여넣기",@"paste:",@"v"],@[@"전체 선택",@"selectAll:",@"a"]];for(NSArray *item in items)[edit addItemWithTitle:item[0] action:NSSelectorFromString(item[1]) keyEquivalent:item[2]];editRoot.submenu=edit;[bar addItem:editRoot];NSMenuItem *vr=[[NSMenuItem alloc]initWithTitle:@"보기" action:nil keyEquivalent:@""];NSMenu *vm=[[NSMenu alloc]initWithTitle:@"보기"];NSMenuItem *reload=[vm addItemWithTitle:@"새로고침" action:@selector(reloadPage:) keyEquivalent:@"r"];reload.target=self;vr.submenu=vm;[bar addItem:vr];NSApp.mainMenu=bar;
 WKWebViewConfiguration *config=[WKWebViewConfiguration new];[config.userContentController addScriptMessageHandler:self name:@"saveStudyPack"];config.websiteDataStore=WKWebsiteDataStore.defaultDataStore;config.mediaTypesRequiringUserActionForPlayback=WKAudiovisualMediaTypeNone;self.web=[[WKWebView alloc]initWithFrame:NSZeroRect configuration:config];self.web.navigationDelegate=self;self.web.UIDelegate=self;
 self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,1240,790) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];self.window.title=@"English Routine";self.window.minSize=NSMakeSize(860,640);[self.window setFrameAutosaveName:@"EnglishRoutineWindow"];self.window.contentView=self.web;[self.window center];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
 [self.web loadHTMLString:@"<body style='background:#f3f4f0;font:16px -apple-system;color:#365e46;display:grid;place-content:center;height:90vh'>English Routine 시작 중…</body>" baseURL:nil];[self startBackend];
}
- (void)startBackend {
 NSURL *res=NSBundle.mainBundle.resourceURL;
 NSTask *p=[NSTask new];
 p.executableURL=[NSURL fileURLWithPath:@"/opt/homebrew/bin/python3"];
 p.arguments=@[[res URLByAppendingPathComponent:@"server.py"].path];
 p.currentDirectoryURL=res;
 NSMutableDictionary *env=[NSProcessInfo.processInfo.environment mutableCopy];
 env[@"PATH"]=@"/Users/jayden/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
 env[@"ENGLISH_PARENT_PID"]=[NSString stringWithFormat:@"%d",NSProcessInfo.processInfo.processIdentifier];
 p.environment=env;
 NSString *logs=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/English Routine"];
 [NSFileManager.defaultManager createDirectoryAtPath:logs withIntermediateDirectories:YES attributes:nil error:nil];
 self.backendLogPath=[logs stringByAppendingPathComponent:@"backend.log"];
 [NSFileManager.defaultManager createFileAtPath:self.backendLogPath contents:nil attributes:nil];
 p.standardError=[NSFileHandle fileHandleForWritingAtPath:self.backendLogPath];
 NSPipe *out=NSPipe.pipe;p.standardOutput=out;
 self.backend=p;self.startupOutput=[NSMutableData new];
 __weak AppDelegate *weakSelf=self;
 out.fileHandleForReading.readabilityHandler=^(NSFileHandle *h){
  NSData *d=h.availableData;
  if(!d.length){h.readabilityHandler=nil;return;}
  dispatch_async(dispatch_get_main_queue(),^{
   AppDelegate *owner=weakSelf;
   if(!owner||owner.startupFinished)return;
   [owner.startupOutput appendData:d];
   NSString *output=[[NSString alloc]initWithData:owner.startupOutput encoding:NSUTF8StringEncoding];
   for(NSString *line in [output componentsSeparatedByString:@"\n"]){
    if(![line hasPrefix:@"READY "]||![output containsString:[line stringByAppendingString:@"\n"]])continue;
    NSURL *url=[NSURL URLWithString:[line substringFromIndex:6]];
    if(![url.scheme isEqual:@"http"]||![url.host isEqual:@"127.0.0.1"]||url.port.intValue<=0)continue;
    owner.startupFinished=YES;owner.serverURL=url;
    [owner.web loadRequest:[NSURLRequest requestWithURL:url]];
    break;
   }
  });
 };
 p.terminationHandler=^(NSTask *task){dispatch_async(dispatch_get_main_queue(),^{
  AppDelegate *owner=weakSelf;
  if(owner&&!owner.stopping){owner.startupFinished=YES;[owner showError:[NSString stringWithFormat:@"학습 엔진이 종료되었습니다. 오류 기록: %@",owner.backendLogPath]];}
 });};
 NSError *error=nil;
 if(![p launchAndReturnError:&error]){self.startupFinished=YES;[self showError:error.localizedDescription];return;}
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{
  AppDelegate *owner=weakSelf;
  if(owner&&!owner.startupFinished&&!owner.stopping){
   owner.startupFinished=YES;owner.backend.terminationHandler=nil;[owner.backend terminate];
   [owner showError:[NSString stringWithFormat:@"학습 엔진을 시작하는 시간이 초과되었습니다. 앱을 다시 열어주세요. 오류 기록: %@",owner.backendLogPath]];
  }
 });
}
- (void)webView:(WKWebView *)view didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
 if(error.code!=NSURLErrorCancelled&&!self.stopping)[self showError:[@"학습 화면을 열지 못했습니다: " stringByAppendingString:error.localizedDescription]];
}
- (void)showError:(NSString *)message {NSAlert *a=[NSAlert new];a.messageText=@"English Routine";a.informativeText=message;[a runModal];}
- (void)showAbout:(id)sender {[self showError:@"8주 영어 루틴 · 팟캐스트 회화 학습\n학습 기록은 이 Mac에 저장됩니다.\n표현 추출: 로그인된 Codex CLI\n자막: 공개 YouTube 영어 자막"];}
- (void)reloadPage:(id)sender {[self.web reload];}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
 if(![message.name isEqual:@"saveStudyPack"]||!message.frameInfo.mainFrame||![message.body isKindOfClass:NSDictionary.class])return;
 NSURL *origin=message.frameInfo.request.URL;
 if(!self.serverURL||![origin.host isEqual:@"127.0.0.1"]||origin.port.intValue!=self.serverURL.port.intValue)return;
 NSString *exportID=message.body[@"exportId"];
 if(![exportID isKindOfClass:NSString.class]||![[NSUUID alloc]initWithUUIDString:exportID])return;
 NSString *name=[exportID.lowercaseString stringByAppendingString:@".podstudy"];
 NSURL *source=[NSURL fileURLWithPath:[[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/English Routine/exports"] stringByAppendingPathComponent:name]];
 NSSavePanel *panel=NSSavePanel.savePanel;panel.nameFieldStringValue=@"Podcast Study.podstudy";panel.message=@"파일 앱이나 AirDrop으로 아이폰에 옮길 학습 꾸러미를 저장합니다.";
 [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result){
  NSString *state=@"cancelled";NSString *detail=@"저장을 취소했습니다. 다시 저장할 수 있습니다.";
  if(result==NSModalResponseOK){
   NSError *error=nil;NSData *contents=[NSData dataWithContentsOfURL:source options:0 error:&error];
   if(contents&&[contents writeToURL:panel.URL options:NSDataWritingAtomic error:&error]){state=@"saved";detail=@"저장했습니다. 아이폰의 파일 앱에서 꾸러미를 가져오세요.";}
   else{state=@"error";detail=error.localizedDescription?:@"파일을 저장하지 못했습니다.";}
  }
  NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"state":state,@"message":detail} options:0 error:nil];
  NSString *script=[NSString stringWithFormat:@"window.dispatchEvent(new CustomEvent('study-pack-saved',{detail:%@}))",[[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding]];
  [self.web evaluateJavaScript:script completionHandler:nil];
 }];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {[self.window makeKeyAndOrderFront:nil];return YES;}
- (void)applicationWillTerminate:(NSNotification *)note {self.stopping=YES;self.backend.terminationHandler=nil;[self.backend terminate];}
- (void)webView:(WKWebView *)view decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))reply {NSURL *u=action.request.URL;if([u.scheme isEqual:@"about"]||([u.host isEqual:@"127.0.0.1"]&&self.serverURL&&u.port.intValue==self.serverURL.port.intValue)){reply(WKNavigationActionPolicyAllow);}else{if([@[@"https",@"http"] containsObject:u.scheme])[NSWorkspace.sharedWorkspace openURL:u];reply(WKNavigationActionPolicyCancel);}}
- (WKWebView *)webView:(WKWebView *)view createWebViewWithConfiguration:(WKWebViewConfiguration *)config forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {NSURL *u=action.request.URL;if([@[@"http",@"https"] containsObject:u.scheme])[NSWorkspace.sharedWorkspace openURL:u];return nil;}
@end
int main(int argc,const char *argv[]){@autoreleasepool{NSApplication *app=NSApplication.sharedApplication;AppDelegate *delegate=[AppDelegate new];[app setActivationPolicy:NSApplicationActivationPolicyRegular];app.delegate=delegate;[app run];}return 0;}

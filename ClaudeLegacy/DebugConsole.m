#import "DebugConsole.h"
#import <unistd.h>
#import <fcntl.h>

@interface PassthroughView : UIView
@end

@implementation PassthroughView
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *sub in self.subviews) {
        if (sub.hidden || sub.alpha < 0.01) continue;
        CGPoint p = [self convertPoint:point toView:sub];
        if ([sub pointInside:p withEvent:event]) return YES;
    }
    return NO;
}
@end

@interface PassthroughViewController : UIViewController
@end

@implementation PassthroughViewController
- (void)loadView {
    self.view = [[PassthroughView alloc] init];
    self.view.backgroundColor = UIColor.clearColor;
}
@end

@interface PassthroughWindow : UIWindow
@end

@implementation PassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

@interface DebugConsole ()
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIView *toast;
@property (nonatomic, strong) UILabel *toastLabel;
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) NSMutableArray<NSString *> *lines;
@property (nonatomic, strong) NSDateFormatter *fmt;
@property (nonatomic, assign) BOOL stderrTapped;
@property (nonatomic, copy) NSString *logPath;
@property (nonatomic, strong) NSFileHandle *logHandle;
@property (nonatomic, copy) void (^dumpHandler)(void);
@end

@implementation DebugConsole

+ (instancetype)shared {
    static DebugConsole *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [DebugConsole new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _lines = [NSMutableArray array];
        _fmt = [NSDateFormatter new];
        _fmt.dateFormat = @"HH:mm:ss.SSS";
        [self openLogFile];
    }
    return self;
}

- (void)openLogFile {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    if (!docs) return;
    NSString *path = [docs stringByAppendingPathComponent:@"debug.log"];
    self.logPath = path;
    // Truncate on each launch so users only see the current session.
    [[NSFileManager defaultManager] createFileAtPath:path contents:[NSData data] attributes:nil];
    self.logHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    NSString *header = [NSString stringWithFormat:@"=== session started %@ ===\n",
                        [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                       dateStyle:NSDateFormatterShortStyle
                                                       timeStyle:NSDateFormatterMediumStyle]];
    [self.logHandle writeData:[header dataUsingEncoding:NSUTF8StringEncoding]];
}

- (NSString *)logFilePath { return self.logPath; }

- (void)setDumpHandler:(void (^)(void))handler { _dumpHandler = [handler copy]; }

- (void)attachToWindowScene:(UIWindowScene *)scene {
    if (self.overlayWindow) return;

    UIWindow *win = [[PassthroughWindow alloc] initWithWindowScene:scene];
    win.windowLevel = UIWindowLevelStatusBar + 100;
    win.backgroundColor = UIColor.clearColor;
    win.hidden = NO;

    PassthroughViewController *vc = [PassthroughViewController new];
    win.rootViewController = vc;
    self.overlayWindow = win;

    UIView *panel = [[UIView alloc] init];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.85];
    panel.layer.cornerRadius = 10;
    panel.hidden = YES;
    [vc.view addSubview:panel];
    self.panel = panel;

    UITextView *tv = [[UITextView alloc] init];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.backgroundColor = UIColor.clearColor;
    tv.textColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    tv.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    tv.editable = NO;
    [panel addSubview:tv];
    self.logView = tv;

    UIButton *clear = [UIButton buttonWithType:UIButtonTypeSystem];
    clear.translatesAutoresizingMaskIntoConstraints = NO;
    [clear setTitle:@"clear" forState:UIControlStateNormal];
    [clear setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    clear.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [clear addTarget:self action:@selector(clearTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:clear];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setTitle:@"close" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [close addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:close];

    UIButton *dump = [UIButton buttonWithType:UIButtonTypeSystem];
    dump.translatesAutoresizingMaskIntoConstraints = NO;
    [dump setTitle:@"dump" forState:UIControlStateNormal];
    [dump setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    dump.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [dump addTarget:self action:@selector(dumpTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:dump];

    UIButton *copyPath = [UIButton buttonWithType:UIButtonTypeSystem];
    copyPath.translatesAutoresizingMaskIntoConstraints = NO;
    [copyPath setTitle:@"copy path" forState:UIControlStateNormal];
    [copyPath setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    copyPath.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [copyPath addTarget:self action:@selector(copyPathTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:copyPath];

    UIButton *hide = [UIButton buttonWithType:UIButtonTypeSystem];
    hide.translatesAutoresizingMaskIntoConstraints = NO;
    [hide setTitle:@"hide overlay" forState:UIControlStateNormal];
    [hide setTitleColor:[UIColor colorWithRed:1.0 green:0.6 blue:0.6 alpha:1.0] forState:UIControlStateNormal];
    hide.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [hide addTarget:self action:@selector(hideOverlayTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:hide];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn setTitle:@"DBG" forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    btn.backgroundColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:0.85];
    btn.layer.cornerRadius = 16;
    [btn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:btn];
    self.toggleButton = btn;

    UIView *toast = [[UIView alloc] init];
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    toast.backgroundColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:0.95];
    toast.layer.cornerRadius = 8;
    toast.hidden = YES;
    toast.userInteractionEnabled = YES;
    [toast addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(togglePanel)]];
    [vc.view addSubview:toast];
    self.toast = toast;

    UILabel *lbl = [UILabel new];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.textColor = UIColor.whiteColor;
    lbl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    lbl.numberOfLines = 3;
    [toast addSubview:lbl];
    self.toastLabel = lbl;

    UILayoutGuide *safe = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:8],
        [panel.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-8],
        [panel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [panel.heightAnchor constraintEqualToAnchor:vc.view.heightAnchor multiplier:0.55],

        [tv.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:8],
        [tv.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-8],
        [tv.topAnchor constraintEqualToAnchor:panel.topAnchor constant:32],
        [tv.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-8],

        [clear.topAnchor constraintEqualToAnchor:panel.topAnchor constant:6],
        [clear.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:12],
        [dump.topAnchor constraintEqualToAnchor:panel.topAnchor constant:6],
        [dump.leadingAnchor constraintEqualToAnchor:clear.trailingAnchor constant:12],
        [copyPath.topAnchor constraintEqualToAnchor:panel.topAnchor constant:6],
        [copyPath.leadingAnchor constraintEqualToAnchor:dump.trailingAnchor constant:12],
        [hide.topAnchor constraintEqualToAnchor:panel.topAnchor constant:6],
        [hide.leadingAnchor constraintEqualToAnchor:copyPath.trailingAnchor constant:12],
        [close.topAnchor constraintEqualToAnchor:panel.topAnchor constant:6],
        [close.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-12],

        [btn.widthAnchor constraintEqualToConstant:44],
        [btn.heightAnchor constraintEqualToConstant:32],
        [btn.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
        [btn.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],

        [toast.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:12],
        [toast.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-12],
        [toast.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [lbl.leadingAnchor constraintEqualToAnchor:toast.leadingAnchor constant:10],
        [lbl.trailingAnchor constraintEqualToAnchor:toast.trailingAnchor constant:-10],
        [lbl.topAnchor constraintEqualToAnchor:toast.topAnchor constant:8],
        [lbl.bottomAnchor constraintEqualToAnchor:toast.bottomAnchor constant:-8],
    ]];

    [self append:@"debug console attached" level:@"info"];
    if (self.logPath) {
        [self append:[NSString stringWithFormat:@"log file: %@", self.logPath] level:@"info"];
    }
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
    self.toast.hidden = YES;
    if (!self.panel.hidden) [self renderLog];
}

- (void)clearTapped {
    [self.lines removeAllObjects];
    [self renderLog];
}

- (void)dumpTapped {
    if (self.dumpHandler) self.dumpHandler();
}

- (void)copyPathTapped {
    if (self.logPath) {
        UIPasteboard.generalPasteboard.string = self.logPath;
        [self append:[NSString stringWithFormat:@"log path copied: %@", self.logPath] level:@"info"];
    }
}

- (void)hideOverlayTapped {
    [self append:@"overlay hidden; kill+relaunch to restore" level:@"info"];
    self.overlayWindow.hidden = YES;
}

- (void)renderLog {
    self.logView.text = [self.lines componentsJoinedByString:@"\n"];
    if (self.logView.text.length > 0) {
        [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length - 1, 1)];
    }
}

- (void)showToast:(NSString *)text {
    self.toastLabel.text = text;
    self.toast.hidden = NO;
    self.toast.alpha = 1.0;
    [UIView animateWithDuration:0.3 delay:5.0 options:0 animations:^{
        self.toast.alpha = 0.0;
    } completion:^(BOOL done) {
        if (done) self.toast.hidden = YES;
    }];
}

- (void)append:(NSString *)line level:(NSString *)level {
    if (!line) return;
    NSString *lvl = level ?: @"log";
    NSString *stamp = [NSString stringWithFormat:@"%@ [%@] %@",
                       [self.fmt stringFromDate:[NSDate date]], lvl, line];
    if (self.logHandle) {
        @try {
            [self.logHandle writeData:[[stamp stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
        } @catch (NSException *e) {}
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.lines addObject:stamp];
        if (self.lines.count > 500) {
            [self.lines removeObjectsInRange:NSMakeRange(0, self.lines.count - 500)];
        }
        if (!self.panel.hidden) [self renderLog];
        if ([lvl isEqualToString:@"error"] || [lvl isEqualToString:@"uncaught"]
            || [lvl isEqualToString:@"promise"] || [lvl isEqualToString:@"nav-fail"]) {
            [self showToast:line];
        }
    });
}

- (void)installStderrTap {
    if (self.stderrTapped) return;
    self.stderrTapped = YES;

    int pipefd[2];
    if (pipe(pipefd) != 0) return;
    dup2(pipefd[1], STDERR_FILENO);
    close(pipefd[1]);

    int readFd = pipefd[0];
    dispatch_queue_t q = dispatch_queue_create("dbg.stderr", DISPATCH_QUEUE_SERIAL);
    dispatch_async(q, ^{
        char buf[4096];
        NSMutableData *acc = [NSMutableData data];
        while (1) {
            ssize_t n = read(readFd, buf, sizeof(buf));
            if (n <= 0) break;
            [acc appendBytes:buf length:n];
            while (1) {
                const char *bytes = acc.bytes;
                NSUInteger len = acc.length;
                NSInteger nl = -1;
                for (NSUInteger i = 0; i < len; i++) {
                    if (bytes[i] == '\n') { nl = i; break; }
                }
                if (nl < 0) break;
                NSString *line = [[NSString alloc] initWithBytes:bytes length:nl encoding:NSUTF8StringEncoding];
                [acc replaceBytesInRange:NSMakeRange(0, nl + 1) withBytes:NULL length:0];
                if (line.length) [self append:line level:@"nslog"];
            }
        }
    });
}

@end

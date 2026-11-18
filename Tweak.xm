#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>
#import <sys/time.h>
#import <substrate.h>

static NSDictionary *getPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.binarycrypted.runtimex.plist"] ?: @{};
}
static BOOL prefBool(NSString *k, BOOL d) { id v = getPrefs()[k]; return v ? [v boolValue] : d; }
static NSInteger prefInt(NSString *k, NSInteger d) { id v = getPrefs()[k]; return v ? [v integerValue] : d; }
static BOOL isRu(void) { return prefInt(@"langIndex", 0) == 1; }
static NSString *L(NSString *e, NSString *r) { return isRu() ? r : e; }

static double g_timeScale = 1.0;
static struct timeval g_baseReal = {0, 0}, g_baseFake = {0, 0};
static BOOL g_timeInit = NO;
static int (*orig_gettimeofday)(struct timeval * __restrict, void * __restrict);

static int hooked_gettimeofday(struct timeval * __restrict tv, void * __restrict tz) {
    int res = orig_gettimeofday(tv, tz);
    if (res == 0 && tv) {
        if (!g_timeInit) { g_baseReal = *tv; g_baseFake = *tv; g_timeInit = YES; return res; }
        double realEl = (tv->tv_sec - g_baseReal.tv_sec) + (tv->tv_usec - g_baseReal.tv_usec) / 1e6;
        double fakeEl = realEl * g_timeScale;
        long s = (long)fakeEl, u = (long)((fakeEl - s) * 1e6);
        tv->tv_sec = g_baseFake.tv_sec + s; tv->tv_usec = g_baseFake.tv_usec + u;
        if (tv->tv_usec >= 1000000) { tv->tv_sec++; tv->tv_usec -= 1000000; }
    }
    return res;
}

static void setGameSpeed(double sp) {
    struct timeval now;
    if (orig_gettimeofday && orig_gettimeofday(&now, NULL) == 0) {
        if (g_timeInit) {
            double realEl = (now.tv_sec - g_baseReal.tv_sec) + (now.tv_usec - g_baseReal.tv_usec) / 1e6;
            double fakeEl = realEl * g_timeScale;
            long s = (long)fakeEl, u = (long)((fakeEl - s) * 1e6);
            g_baseFake.tv_sec += s; g_baseFake.tv_usec += u;
            if (g_baseFake.tv_usec >= 1000000) { g_baseFake.tv_sec++; g_baseFake.tv_usec -= 1000000; }
            g_baseReal = now;
        } else { g_baseReal = now; g_baseFake = now; g_timeInit = YES; }
    }
    g_timeScale = sp;
}

static NSMutableArray<NSNumber *> *g_addrs = nil;
static BOOL g_isFloat = NO;
static NSTimer *g_freezeTimer = nil;
static int32_t g_fInt = 0;
static float g_fFloat = 0.0f;

static NSUInteger scanMem(double target, BOOL isFlt, BOOL filter) {
    if (!g_addrs) g_addrs = [NSMutableArray array];
    g_isFloat = isFlt;
    mach_port_t task = mach_task_self();
    if (filter && g_addrs.count > 0) {
        NSMutableArray *res = [NSMutableArray array];
        for (NSNumber *n in g_addrs) {
            mach_vm_address_t a = [n unsignedLongLongValue];
            mach_vm_size_t out = isFlt ? 4 : 4;
            if (isFlt) {
                float v = 0;
                if (mach_vm_read_overwrite(task, a, 4, (mach_vm_address_t)&v, &out) == KERN_SUCCESS && fabsf(v - (float)target) < 0.05f) [res addObject:n];
            } else {
                int32_t v = 0;
                if (mach_vm_read_overwrite(task, a, 4, (mach_vm_address_t)&v, &out) == KERN_SUCCESS && v == (int32_t)target) [res addObject:n];
            }
        }
        g_addrs = res; return g_addrs.count;
    }
    [g_addrs removeAllObjects];
    mach_vm_address_t addr = 0; mach_vm_size_t sz = 0;
    while (1) {
        mach_msg_type_number_t cnt = VM_REGION_BASIC_INFO_COUNT_64;
        vm_region_basic_info_data_64_t info; mach_port_t obj = MACH_PORT_NULL;
        if (mach_vm_region(task, &addr, &sz, VM_REGION_BASIC_INFO_COUNT_64, (vm_region_info_t)&info, &cnt, &obj) != KERN_SUCCESS) break;
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE) && sz > 0 && sz < 64*1024*1024) {
            NSMutableData *buf = [NSMutableData dataWithLength:(NSUInteger)sz];
            mach_vm_size_t rd = 0;
            if (mach_vm_read_overwrite(task, addr, sz, (mach_vm_address_t)buf.mutableBytes, &rd) == KERN_SUCCESS) {
                NSUInteger n = (NSUInteger)(rd / 4);
                if (isFlt) {
                    const float *p = (const float *)buf.bytes;
                    for (NSUInteger i = 0; i < n; i++) if (fabsf(p[i] - (float)target) < 0.05f) { [g_addrs addObject:@(addr + i*4)]; if (g_addrs.count >= 5000) break; }
                } else {
                    const int32_t *p = (const int32_t *)buf.bytes;
                    for (NSUInteger i = 0; i < n; i++) if (p[i] == (int32_t)target) { [g_addrs addObject:@(addr + i*4)]; if (g_addrs.count >= 5000) break; }
                }
            }
        }
        if (g_addrs.count >= 5000) break;
        addr += sz;
    }
    return g_addrs.count;
}

static NSUInteger writeMem(double val, BOOL isFlt) {
    if (!g_addrs.count) return 0;
    mach_port_t task = mach_task_self(); NSUInteger w = 0;
    int32_t iv = (int32_t)val; float fv = (float)val;
    for (NSNumber *n in g_addrs) {
        if (mach_vm_write(task, [n unsignedLongLongValue], isFlt ? (vm_offset_t)&fv : (vm_offset_t)&iv, 4) == KERN_SUCCESS) w++;
    }
    return w;
}
@interface HexInterpreter : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *vars;
@property (nonatomic, strong) NSMutableArray<NSTimer *> *timers;
@property (nonatomic, copy) void (^logHandler)(NSString *msg);
- (void)exec:(NSString *)script;
- (void)stopAll;
@end

@implementation HexInterpreter
- (instancetype)init {
    if (self = [super init]) { _vars = [NSMutableDictionary dictionary]; _timers = [NSMutableArray array]; }
    return self;
}
- (void)log:(NSString *)t {
    if (self.logHandler) dispatch_async(dispatch_get_main_queue(), ^{ self.logHandler(t); });
}
- (void)stopAll {
    for (NSTimer *t in self.timers) [t invalidate];
    [self.timers removeAllObjects];
    if (g_freezeTimer) { [g_freezeTimer invalidate]; g_freezeTimer = nil; }
    [self log:L(@"[SYS] Stopped.", @"[SYS] Остановлено.")];
}
- (NSString *)unquote:(NSString *)s {
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return ([s hasPrefix:@"\""] && [s hasSuffix:@"\""] && s.length >= 2) ? [s substringWithRange:NSMakeRange(1, s.length - 2)] : s;
}
- (id)eval:(NSString *)expr {
    expr = [expr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([expr containsString:@"+"]) {
        NSMutableString *res = [NSMutableString string]; BOOL isStr = NO; double sum = 0;
        for (NSString *rp in [expr componentsSeparatedByString:@"+"]) {
            NSString *p = [rp stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([p hasPrefix:@"\""] && [p hasSuffix:@"\""] && p.length >= 2) { isStr = YES; [res appendString:[self unquote:p]]; }
            else if (self.vars[p]) {
                id v = self.vars[p];
                if ([v isKindOfClass:[NSString class]]) { isStr = YES; [res appendString:v]; }
                else { sum += [v doubleValue]; [res appendFormat:@"%@", v]; }
            } else { sum += [p doubleValue]; [res appendString:p]; }
        }
        return isStr ? res : ((floor(sum) == sum) ? @((long long)sum) : @(sum));
    }
    for (NSString *op in @[@"*", @"/", @"-"]) {
        NSRange r = [expr rangeOfString:op];
        if (r.location != NSNotFound && r.location > 0) {
            NSString *ls = [[expr substringToIndex:r.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *rs = [[expr substringFromIndex:r.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            double l = self.vars[ls] ? [self.vars[ls] doubleValue] : [ls doubleValue];
            double ri = self.vars[rs] ? [self.vars[rs] doubleValue] : [rs doubleValue];
            double v = [op isEqualToString:@"*"] ? l*ri : ([op isEqualToString:@"/"] && ri != 0 ? l/ri : l-ri);
            return (floor(v) == v) ? @((long long)v) : @(v);
        }
    }
    if ([expr hasPrefix:@"\""] && [expr hasSuffix:@"\""] && expr.length >= 2) return [self unquote:expr];
    if (self.vars[expr]) return self.vars[expr];
    if ([expr isEqualToString:@"true"]) return @YES;
    if ([expr isEqualToString:@"false"]) return @NO;
    return @([expr doubleValue]);
}
- (BOOL)evalCond:(NSString *)c {
    for (NSString *op in @[@"==", @"!=", @"<=", @">=", @"<", @">"]) {
        NSRange r = [c rangeOfString:op];
        if (r.location != NSNotFound) {
            double l = [[self eval:[c substringToIndex:r.location]] doubleValue];
            double ri = [[self eval:[c substringFromIndex:r.location + op.length]] doubleValue];
            if ([op isEqualToString:@"=="]) return fabs(l - ri) < 1e-4;
            if ([op isEqualToString:@"!="]) return fabs(l - ri) >= 1e-4;
            if ([op isEqualToString:@"<="]) return l <= ri;
            if ([op isEqualToString:@">="]) return l >= ri;
            if ([op isEqualToString:@"<"]) return l < ri;
            if ([op isEqualToString:@">"]) return l > ri;
        }
    }
    return [[self eval:c] boolValue];
}
- (void)exec:(NSString *)script {
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *raw in [script componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSRange cm = [raw rangeOfString:@"#"];
        NSString *cl = (cm.location != NSNotFound) ? [raw substringToIndex:cm.location] : raw;
        cl = [cl stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (cl.length > 0) [lines addObject:cl];
    }
    NSUInteger i = 0;
    while (i < lines.count) {
        NSString *ln = lines[i];
        if (([ln hasPrefix:@"if "] || [ln hasPrefix:@"repeat "] || [ln hasPrefix:@"every "]) && [ln hasSuffix:@"{"]) {
            NSMutableArray *blk = [NSMutableArray array]; i++;
            while (i < lines.count && ![lines[i] isEqualToString:@"}"]) { [blk addObject:lines[i]]; i++; }
            NSString *sub = [blk componentsJoinedByString:@"\n"];
            if ([ln hasPrefix:@"if "] && [self evalCond:[ln substringWithRange:NSMakeRange(3, ln.length - 4)]]) [self exec:sub];
            else if ([ln hasPrefix:@"repeat "]) {
                NSInteger cnt = [[self eval:[ln substringWithRange:NSMakeRange(7, ln.length - 8)]] integerValue];
                for (NSInteger r = 0; r < cnt; r++) [self exec:sub];
            } else if ([ln hasPrefix:@"every "]) {
                double sec = MAX(0.05, [[self eval:[ln substringWithRange:NSMakeRange(6, ln.length - 7)]] doubleValue]);
                __weak typeof(self) ws = self;
                [self.timers addObject:[NSTimer scheduledTimerWithTimeInterval:sec repeats:YES block:^(NSTimer *t) { [ws exec:sub]; }]];
            }
            i++; continue;
        }
        [self execLine:ln]; i++;
    }
}
- (void)execLine:(NSString *)ln {
    if ([ln hasPrefix:@"let "]) {
        NSRange eq = [ln rangeOfString:@"="];
        if (eq.location != NSNotFound) {
            NSString *k = [[ln substringWithRange:NSMakeRange(4, eq.location - 4)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            id v = [self eval:[ln substringFromIndex:eq.location + 1]];
            self.vars[k] = v; [self log:[NSString stringWithFormat:@"[VAR] %@ = %@", k, v]];
        }
    } else if ([ln hasPrefix:@"print "]) { [self log:[NSString stringWithFormat:@"> %@", [self eval:[ln substringFromIndex:6]]]]; }
    else if ([ln hasPrefix:@"sys.speed "]) { double s = MAX(0.05, [[self eval:[ln substringFromIndex:10]] doubleValue]); setGameSpeed(s); [self log:[NSString stringWithFormat:@"[SPEED] %.2fx", s]]; }
    else if ([ln isEqualToString:@"sys.info"]) { [self log:[NSString stringWithFormat:@"[SYS] %@ | PID:%d | %.2fx | Addrs:%lu", [[NSBundle mainBundle] bundleIdentifier], getpid(), g_timeScale, (unsigned long)g_addrs.count]]; }
    else if ([ln isEqualToString:@"stop"]) { [self stopAll]; }
    else if ([ln hasPrefix:@"mem.scan_float "]) { double v = [[self eval:[ln substringFromIndex:15]] doubleValue]; [self log:[NSString stringWithFormat:@"[MEM-F] %lu matches", (unsigned long)scanMem(v, YES, NO)]]; }
    else if ([ln hasPrefix:@"mem.filter_float "]) { double v = [[self eval:[ln substringFromIndex:17]] doubleValue]; [self log:[NSString stringWithFormat:@"[MEM-F] %lu left", (unsigned long)scanMem(v, YES, YES)]]; }
    else if ([ln hasPrefix:@"mem.write_float "]) { double v = [[self eval:[ln substringFromIndex:16]] doubleValue]; [self log:[NSString stringWithFormat:@"[MEM-F] Wrote %lu", (unsigned long)writeMem(v, YES)]]; }
    else if ([ln hasPrefix:@"mem.scan "]) { double v = [[self eval:[ln substringFromIndex:9]] doubleValue]; [self log:[NSString stringWithFormat:@"[MEM] %lu matches", (unsigned long)scanMem(v, NO, NO)]]; }
    else if ([ln hasPrefix:@"mem.filter "]) { double v = [[self eval:[ln substringFromIndex:11]] doubleValue]; [self log:[NSString stringWithFormat:@"[MEM] %lu left", (unsigned long)scanMem(v, NO, YES)]]; }
    else if ([ln hasPrefix:@"mem.write "]) { double v = [[self eval:[ln substringFromIndex:10]] doubleValue]; [self log:[NSString stringWithFormat:@"[MEM] Wrote %lu", (unsigned long)writeMem(v, NO)]]; }
    else if ([ln hasPrefix:@"mem.freeze "]) {
        if (g_freezeTimer) [g_freezeTimer invalidate];
        double v = [[self eval:[ln substringFromIndex:11]] doubleValue];
        if (g_isFloat) { g_fFloat = (float)v; g_freezeTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *t) { writeMem(g_fFloat, YES); }]; }
        else { g_fInt = (int32_t)v; g_freezeTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *t) { writeMem(g_fInt, NO); }]; }
        [self log:@"[MEM] Freeze active"];
    } else if ([ln isEqualToString:@"mem.unfreeze"]) { if (g_freezeTimer) { [g_freezeTimer invalidate]; g_freezeTimer = nil; } [self log:@"[MEM] Unfrozen"]; }
    else if ([ln isEqualToString:@"mem.list"]) {
        NSMutableArray *d = [NSMutableArray array];
        for (NSUInteger k = 0; k < MIN(g_addrs.count, 10); k++) [d addObject:[NSString stringWithFormat:@"0x%llx", [g_addrs[k] unsignedLongLongValue]]];
        [self log:[NSString stringWithFormat:@"[ADDR] %@", d.count ? [d componentsJoinedByString:@", "] : @"empty"]];
    } else if ([ln hasPrefix:@"objc.find "]) {
        NSString *q = [[self unquote:[ln substringFromIndex:10]] lowercaseString]; unsigned int c = 0; Class *cls = objc_copyClassList(&c);
        NSMutableArray *m = [NSMutableArray array];
        for (unsigned int k = 0; k < c; k++) { NSString *nm = NSStringFromClass(cls[k]); if ([[nm lowercaseString] containsString:q]) { [m addObject:nm]; if (m.count >= 20) break; } }
        free(cls); [self log:[NSString stringWithFormat:@"[OBJC] %@", [m componentsJoinedByString:@", "]]];
    } else if ([ln hasPrefix:@"objc.methods "]) {
        Class cls = NSClassFromString([self unquote:[ln substringFromIndex:13]]);
        if (!cls) { [self log:@"[ERR] Class not found"]; return; }
        unsigned int c = 0; Method *ms = class_copyMethodList(cls, &c); NSMutableArray *m = [NSMutableArray array];
        for (unsigned int k = 0; k < c; k++) { [m addObject:NSStringFromSelector(method_getName(ms[k]))]; if (m.count >= 30) break; }
        free(ms); [self log:[NSString stringWithFormat:@"[OBJC] %@", [m componentsJoinedByString:@", "]]];
    } else if ([ln hasPrefix:@"objc.hook "]) {
        NSArray *pts = [[ln substringFromIndex:10] componentsSeparatedByString:@"->"];
        if (pts.count == 2) {
            NSString *tgt = [self unquote:pts[0]], *vs = [pts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSRange dot = [tgt rangeOfString:@"."];
            if (dot.location != NSNotFound) {
                Class cls = NSClassFromString([tgt substringToIndex:dot.location]);
                SEL sel = NSSelectorFromString([tgt substringFromIndex:dot.location + 1]);
                Method m = class_getInstanceMethod(cls, sel) ?: class_getInstanceMethod(object_getClass(cls), sel);
                if (m) {
                    if ([vs isEqualToString:@"true"]) method_setImplementation(m, imp_implementationWithBlock(^BOOL(id s) { return YES; }));
                    else if ([vs isEqualToString:@"false"]) method_setImplementation(m, imp_implementationWithBlock(^BOOL(id s) { return NO; }));
                    else { long long num = [[self eval:vs] longLongValue]; method_setImplementation(m, imp_implementationWithBlock(^long long(id s) { return num; })); }
                    [self log:[NSString stringWithFormat:@"[HOOK] %@ -> %@", tgt, vs]];
                } else [self log:@"[ERR] Method not found"];
            }
        }
    } else if ([ln isEqualToString:@"help"]) {
        [self log:@"let x=1 | if x>0 {} | repeat 3 {} | every 1.0 {} | mem.scan/filter/write/freeze/list | mem.scan_float/write_float | objc.find/methods/hook | sys.speed 0.5 | stop"];
    } else { [self log:[NSString stringWithFormat:@"[ERR] %@", ln]]; }
}
@end
@interface RuntimeXOverlay : NSObject
@property (nonatomic, strong) UIWindow *hudWindow;
@property (nonatomic, strong) UIButton *floatingBtn;
@property (nonatomic, strong) UIView *consolePanel;
@property (nonatomic, strong) UITextView *outputView;
@property (nonatomic, strong) UITextView *inputView;
@property (nonatomic, strong) HexInterpreter *interpreter;
+ (instancetype)shared;
- (void)setup;
@end

@implementation RuntimeXOverlay

+ (instancetype)shared {
    static RuntimeXOverlay *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [[RuntimeXOverlay alloc] init]; });
    return inst;
}

- (UIColor *)accentColor {
    NSInteger theme = prefInt(@"themeIndex", 0);
    if (theme == 1) return [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:1.0];
    if (theme == 2) return [UIColor colorWithRed:1.0 green:0.72 blue:0.0 alpha:1.0];
    return [UIColor colorWithRed:0.0 green:0.95 blue:0.55 alpha:1.0];
}

- (void)setup {
    if (self.hudWindow || !prefBool(@"enabled", YES)) return;
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    if ([bid isEqualToString:@"com.apple.springboard"]) return;
    if (prefBool(@"hideInAppleApps", YES) && [bid hasPrefix:@"com.apple."]) return;

    UIColor *accent = [self accentColor];
    self.interpreter = [[HexInterpreter alloc] init];
    __weak typeof(self) ws = self;
    self.interpreter.logHandler = ^(NSString *msg) {
        ws.outputView.text = [(ws.outputView.text ?: @"") stringByAppendingFormat:@"%@\n", msg];
        if (ws.outputView.text.length > 0) [ws.outputView scrollRangeToVisible:NSMakeRange(ws.outputView.text.length - 1, 1)];
    };

    CGRect bounds = [UIScreen mainScreen].bounds;
    self.hudWindow = [[UIWindow alloc] initWithFrame:bounds];
    self.hudWindow.windowLevel = UIWindowLevelAlert + 500;
    self.hudWindow.backgroundColor = [UIColor clearColor];
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor clearColor];
    self.hudWindow.rootViewController = vc;

    self.floatingBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatingBtn.frame = CGRectMake(bounds.size.width - 52, 60, 42, 42);
    self.floatingBtn.backgroundColor = [UIColor colorWithRed:0.06 green:0.08 blue:0.12 alpha:0.9];
    self.floatingBtn.layer.cornerRadius = 21;
    self.floatingBtn.layer.borderWidth = 1.5;
    self.floatingBtn.layer.borderColor = accent.CGColor;
    [self.floatingBtn setTitle:@"</>" forState:UIControlStateNormal];
    [self.floatingBtn setTitleColor:accent forState:UIControlStateNormal];
    self.floatingBtn.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:13];
    [self.floatingBtn addTarget:self action:@selector(toggleConsole) forControlEvents:UIControlEventTouchUpInside];
    [self.floatingBtn addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)]];
    [vc.view addSubview:self.floatingBtn];

    CGFloat pW = bounds.size.width - 24;
    self.consolePanel = [[UIView alloc] initWithFrame:CGRectMake(12, 50, pW, 264)];
    self.consolePanel.backgroundColor = [UIColor colorWithRed:0.05 green:0.06 blue:0.09 alpha:0.95];
    self.consolePanel.layer.cornerRadius = 10;
    self.consolePanel.layer.borderWidth = 1.2;
    self.consolePanel.layer.borderColor = accent.CGColor;
    self.consolePanel.hidden = YES;
    [vc.view addSubview:self.consolePanel];

    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, 200, 20)];
    titleLbl.text = @"RuntimeX // HexLang 2.0";
    titleLbl.textColor = accent;
    titleLbl.font = [UIFont fontWithName:@"Menlo-Bold" size:12];
    [self.consolePanel addSubview:titleLbl];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(pW - 34, 4, 28, 24);
    [closeBtn setTitle:@"X" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:13];
    [closeBtn addTarget:self action:@selector(toggleConsole) forControlEvents:UIControlEventTouchUpInside];
    [self.consolePanel addSubview:closeBtn];

    self.outputView = [[UITextView alloc] initWithFrame:CGRectMake(8, 30, pW - 16, 118)];
    self.outputView.backgroundColor = [UIColor colorWithWhite:0.02 alpha:0.85];
    self.outputView.textColor = accent;
    self.outputView.font = [UIFont fontWithName:@"Menlo" size:10];
    self.outputView.editable = NO;
    self.outputView.layer.cornerRadius = 6;
    self.outputView.text = L(@"RuntimeX v2.0 Ready. Type 'help'.\n", @"RuntimeX v2.0 готов. Введите 'help'.\n");
    [self.consolePanel addSubview:self.outputView];

    self.inputView = [[UITextView alloc] initWithFrame:CGRectMake(8, 154, pW - 16, 66)];
    self.inputView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.9];
    self.inputView.textColor = [UIColor whiteColor];
    self.inputView.font = [UIFont fontWithName:@"Menlo" size:11];
    self.inputView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.inputView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.inputView.layer.cornerRadius = 6;
    self.inputView.text = @"sys.info";
    [self.consolePanel addSubview:self.inputView];

    CGFloat bW = (pW - 34) / 4.0;
    NSArray *titles = isRu() ? @[@"ПУСК", @"ФАЙЛ", @"ОЧИСТ", @"СТОП"] : @[@"RUN", @"LOAD", @"CLEAR", @"STOP"];
    SEL actions = {@selector(runScript), @selector(loadScript), @selector(clearLog), @selector(stopAll)};
    for (int b = 0; b < 4; b++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(8 + b * (bW + 6), 226, bW, 28);
        btn.backgroundColor = (b == 0) ? [accent colorWithAlphaComponent:0.75] : [UIColor colorWithWhite:0.2 alpha:0.9];
        btn.layer.cornerRadius = 5;
        [btn setTitle:titles[b] forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:11];
        [btn addTarget:self action:actions[b] forControlEvents:UIControlEventTouchUpInside];
        [self.consolePanel addSubview:btn];
    }
    self.hudWindow.hidden = NO;

    if (prefBool(@"autoRunScript", NO)) {
        NSString *code = [NSString stringWithContentsOfFile:@"/var/mobile/Documents/autorun.hex" encoding:NSUTF8StringEncoding error:nil];
        if (code.length > 0) [self.interpreter exec:code];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self.hudWindow];
    self.floatingBtn.center = CGPointMake(self.floatingBtn.center.x + t.x, self.floatingBtn.center.y + t.y);
    [p setTranslation:CGPointZero inView:self.hudWindow];
}
- (void)toggleConsole { self.consolePanel.hidden = !self.consolePanel.hidden; if (self.consolePanel.hidden) [self.inputView resignFirstResponder]; }
- (void)runScript { [self.inputView resignFirstResponder]; if (self.inputView.text.length) [self.interpreter exec:self.inputView.text]; }
- (void)loadScript {
    NSString *c = [NSString stringWithContentsOfFile:@"/var/mobile/Documents/script.hex" encoding:NSUTF8StringEncoding error:nil];
    if (c) { self.inputView.text = c; [self.interpreter log:@"[FILE] Loaded script.hex"]; }
    else [self.interpreter log:@"[ERR] Missing script.hex"];
}
- (void)clearLog { self.outputView.text = @""; }
- (void)stopAll { [self.interpreter stopAll]; setGameSpeed(1.0); }
@end

@interface UIWindow (RuntimeXPass)
@end
@implementation UIWindow (RuntimeXPass)
- (UIView *)rx_hitTest:(CGPoint)pt withEvent:(UIEvent *)ev {
    UIView *h = [self rx_hitTest:pt withEvent:ev];
    return (self == [RuntimeXOverlay shared].hudWindow && (h == self || h == self.rootViewController.view)) ? nil : h;
}
@end

%ctor {
    if (!prefBool(@"enabled", YES)) return;
    MSHookFunction((void *)gettimeofday, (void *)hooked_gettimeofday, (void **)&orig_gettimeofday);
    Method o = class_getInstanceMethod([UIWindow class], @selector(hitTest:withEvent:));
    Method s = class_getInstanceMethod([UIWindow class], @selector(rx_hitTest:withEvent:));
    if (o && s) method_exchangeImplementations(o, s);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [[RuntimeXOverlay shared] setup]; });
}

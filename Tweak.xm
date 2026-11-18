#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>
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
            vm_address_t a = (vm_address_t)[n unsignedLongValue];
            vm_size_t out = 4;
            if (isFlt) {
                float v = 0;
                if (vm_read_overwrite(task, a, 4, (vm_address_t)&v, &out) == KERN_SUCCESS && fabsf(v - (float)target) < 0.05f) [res addObject:n];
            } else {
                int32_t v = 0;
                if (vm_read_overwrite(task, a, 4, (vm_address_t)&v, &out) == KERN_SUCCESS && v == (int32_t)target) [res addObject:n];
            }
        }
        g_addrs = res; return g_addrs.count;
    }
    [g_addrs removeAllObjects];
    vm_address_t addr = 0; vm_size_t sz = 0;
    while (1) {
        mach_msg_type_number_t cnt = VM_REGION_BASIC_INFO_COUNT;
        vm_region_basic_info_data_t info; mach_port_t obj = MACH_PORT_NULL;
        if (vm_region(task, &addr, &sz, VM_REGION_BASIC_INFO, (vm_region_info_t)&info, &cnt, &obj) != KERN_SUCCESS) break;
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE) && sz > 0 && sz < 64*1024*1024) {
            NSMutableData *buf = [NSMutableData dataWithLength:(NSUInteger)sz];
            vm_size_t rd = 0;
            if (vm_read_overwrite(task, addr, sz, (vm_address_t)buf.mutableBytes, &rd) == KERN_SUCCESS) {
                NSUInteger n = (NSUInteger)(rd / 4);
                if (isFlt) {
                    const float *p = (const float *)buf.bytes;
                    for (NSUInteger i = 0; i < n; i++) if (fabsf(p[i] - (float)target) < 0.05f) { [g_addrs addObject:@((unsigned long)(addr + i*4))]; if (g_addrs.count >= 5000) break; }
                } else {
                    const int32_t *p = (const int32_t *)buf.bytes;
                    for (NSUInteger i = 0; i < n; i++) if (p[i] == (int32_t)target) { [g_addrs addObject:@((unsigned long)(addr + i*4))]; if (g_addrs.count >= 5000) break; }
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
        if (vm_write(task, (vm_address_t)[n unsignedLongValue], isFlt ? (vm_offset_t)&fv : (vm_offset_t)&iv, 4) == KERN_SUCCESS) w++;
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

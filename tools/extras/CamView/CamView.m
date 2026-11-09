// CamView — 摄像头实时预览（CPU 渲染，绕开 CoreImage/Metal 缺陷）
// 背景：NullMoth 驱动下 CIRenderDestination 渲染永不完成，导致 Photo Booth 黑屏。
// 本程序完全不走 CoreImage/Metal：CVPixelBuffer(BGRA) → CGImage → Core Graphics 绘制。

#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

static NSString *const kAppName = @"摄像头预览";

static void LOG(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], m];
    FILE *f = fopen("/tmp/camview.log", "a");
    if (f) { fputs(line.UTF8String, f); fclose(f); }
}


#pragma mark - 预览视图

@interface PreviewView : NSView
@property (nonatomic, strong) NSImage *snapshotImage;
- (void)setFrameImage:(CGImageRef)img;
- (CGImageRef)copyCurrentImage CF_RETURNS_RETAINED;
@property (nonatomic) BOOL mirror;
@property (nonatomic) long frames;
@property (nonatomic, readonly) CGImageRef lastImageRef;
- (BOOL)hasImage;
@end

@implementation PreviewView {
    CGImageRef _img;
    NSTimeInterval _lastTick;
    double _fps;
    NSTextField *_hud;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);
        _mirror = YES;
        _hud = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 12, 260, 20)];
        _hud.editable = NO;
        _hud.bordered = NO;
        _hud.drawsBackground = NO;
        _hud.selectable = NO;
        _hud.textColor = [NSColor colorWithWhite:0.95 alpha:0.85];
        _hud.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
        _hud.stringValue = @"正在启动摄像头…";
        [self addSubview:_hud];
    }
    return self;
}

- (BOOL)isOpaque { return YES; }

- (void)setFrameImage:(CGImageRef)img {
    if (!img) return;
    if (_img) CGImageRelease(_img);
    _img = CGImageRetain(img);
    _frames++;

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (_lastTick == 0) _lastTick = now;
    if (now - _lastTick >= 0.5) {
        _fps = _frames / (now - _lastTick);
        _frames = 0;
        _lastTick = now;
        _hud.stringValue = [NSString stringWithFormat:@"%zux%zu   %.1f fps   镜像:%@",
                            CGImageGetWidth(_img), CGImageGetHeight(_img), _fps,
                            _mirror ? @"开" : @"关"];
        /* 心跳文件：供外部验证是否真的在出帧 */
        NSString *hb = [NSString stringWithFormat:@"%@ %zux%zu %.1f fps",
                        [NSDate date], CGImageGetWidth(_img), CGImageGetHeight(_img), _fps];
        [hb writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@".camview_status"]
             atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    [self setNeedsDisplay:YES];
}

- (BOOL)hasImage { return _img != NULL; }
- (CGImageRef)lastImageRef { return _img; }

- (CGImageRef)copyCurrentImage {
    return _img ? CGImageRetain(_img) : NULL;
}

- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef c = [[NSGraphicsContext currentContext] CGContext];
    CGContextSetRGBFillColor(c, 0, 0, 0, 1);
    CGContextFillRect(c, self.bounds);
    if (!_img) return;

    /* 等比适配（letterbox） */
    CGFloat iw = CGImageGetWidth(_img), ih = CGImageGetHeight(_img);
    if (iw <= 0 || ih <= 0) return;
    NSRect b = self.bounds;
    CGFloat scale = MIN(NSWidth(b) / iw, NSHeight(b) / ih);
    NSRect dst = NSMakeRect((NSWidth(b) - iw * scale) / 2.0,
                            (NSHeight(b) - ih * scale) / 2.0,
                            iw * scale, ih * scale);

    CGContextSaveGState(c);
    if (_mirror) {
        CGContextTranslateCTM(c, NSMidX(dst) * 2.0, 0);
        CGContextScaleCTM(c, -1, 1);
    }
    CGContextSetInterpolationQuality(c, kCGInterpolationMedium);
    CGContextDrawImage(c, dst, _img);
    CGContextRestoreGState(c);
}

- (void)dealloc {
    if (_img) CGImageRelease(_img);
}
@end

#pragma mark - 采集

@interface Capture : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, weak) PreviewView *view;
@property (nonatomic, strong) AVCaptureDevice *device;
@property (nonatomic) BOOL paused;
@end

@implementation Capture

- (BOOL)startWithError:(NSString **)errMsg {
    LOG(@"startWithError 开始");
    NSArray *devs = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    LOG(@"设备数 = %lu", (unsigned long)devs.count);
    if (devs.count == 0) { if (errMsg) *errMsg = @"没有检测到摄像头设备"; return NO; }
    self.device = devs.firstObject;

    /* 权限 */
    AVAuthorizationStatus st = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    LOG(@"TCC 状态 = %ld", (long)st);
    if (st == AVAuthorizationStatusDenied || st == AVAuthorizationStatusRestricted) {
        LOG(@"TCC 判定被拒，仍尝试直接打开设备（继承启动方的授权）");
    }

    LOG(@"准备创建 session");
    self.session = [[AVCaptureSession alloc] init];
    [self.session beginConfiguration];
    if ([self.session canSetSessionPreset:AVCaptureSessionPresetHigh])
        self.session.sessionPreset = AVCaptureSessionPresetHigh;
    LOG(@"预设 = %@", self.session.sessionPreset);

    NSError *e = nil;
    AVCaptureDeviceInput *in = [AVCaptureDeviceInput deviceInputWithDevice:self.device error:&e];
    if (!in) { if (errMsg) *errMsg = e.localizedDescription ?: @"无法打开摄像头"; return NO; }
    BOOL okIn = [self.session canAddInput:in];
    LOG(@"canAddInput = %d", okIn);
    if (okIn) [self.session addInput:in];

    AVCaptureVideoDataOutput *out = [[AVCaptureVideoDataOutput alloc] init];
    out.alwaysDiscardsLateVideoFrames = YES;
    /* 强制 BGRA：让系统做格式转换，避免双平面 YCbCr 读错色 */
    if (!getenv("CAMVIEW_NOFMT")) {
        out.videoSettings = @{ (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
    }
    LOG(@"videoSettings 设定后 = %@", out.videoSettings);
    [out setSampleBufferDelegate:self queue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)];
    BOOL okOut = [self.session canAddOutput:out];
    LOG(@"canAddOutput = %d  格式=%@", okOut, out.videoSettings);
    if (okOut) [self.session addOutput:out];
    /* 连接参数 */
    for (AVCaptureConnection *c in out.connections) {
        LOG(@"  connection enabled=%d  active=%d", c.isEnabled, c.isActive);
    }

    [self.session commitConfiguration];
    LOG(@"commit 完成，开始 startRunning");
    [self.session startRunning];
    LOG(@"startRunning 返回");
    return YES;
}

- (void)stop { [self.session stopRunning]; }

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    if (self.paused) return;
    static int first = 1;
    if (first) { first = 0; LOG(@"收到第一帧回调"); }
    CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pb) return;

    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    size_t w = CVPixelBufferGetWidth(pb);
    size_t h = CVPixelBufferGetHeight(pb);
    size_t bpr = CVPixelBufferGetBytesPerRow(pb);
    uint8_t *base = (uint8_t *)CVPixelBufferGetBaseAddress(pb);
    if (!base || w == 0 || h == 0) { CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly); return; }

    size_t tight = w * 4;
    uint8_t *dst = malloc(tight * h);
    if (dst) {
        for (size_t y = 0; y < h; y++) {
            uint8_t *src = base + y * bpr;
            uint8_t *row = dst + y * tight;
            memcpy(row, src, tight);
            /* 强制 alpha=255，避免驱动给出 0 导致整幅透明 */
            for (size_t x = 3; x < tight; x += 4) row[x] = 255;
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    if (!dst) return;

    /* BGRA 内存布局：byteOrder32Little + NoneSkipFirst 即为正确解释 */
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef bctx = CGBitmapContextCreate(dst, w, h, 8, tight, cs,
                                              kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst);
    if (bctx) {
        CGImageRef img = CGBitmapContextCreateImage(bctx);
        if (img) {
            static int firstDraw = 1;
            if (firstDraw) { firstDraw = 0; LOG(@"首帧 CGImage 创建成功 %zux%zu", w, h); }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.view setFrameImage:img];
            });
            CGImageRelease(img);
        }
        CGContextRelease(bctx);
    }
    CGColorSpaceRelease(cs);
    free(dst);
}
@end

#pragma mark - 主控制器

@interface Controller : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) PreviewView *view;
@property (nonatomic, strong) Capture *cap;
@property (nonatomic, strong) NSTextField *status;
@end

@implementation Controller

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    NSRect frame = NSMakeRect(0, 0, 960, 540);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = kAppName;
    self.window.delegate = self;
    self.window.backgroundColor = [NSColor blackColor];
    [self.window center];

    NSView *content = self.window.contentView;

    self.view = [[PreviewView alloc] initWithFrame:content.bounds];
    self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:self.view];

    /* 底部控制条 */
    CGFloat barH = 44;
    NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(content.bounds), barH)];
    bar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    bar.wantsLayer = YES;
    bar.layer.backgroundColor = [[NSColor colorWithWhite:0.12 alpha:0.92] CGColor];

    NSButton *shoot = [NSButton buttonWithTitle:@"拍照 (空格)" target:self action:@selector(snapshot:)];
    shoot.frame = NSMakeRect(12, 8, 120, 28);
    shoot.bezelStyle = NSBezelStyleRounded;
    [bar addSubview:shoot];

    NSButton *mirror = [NSButton checkboxWithTitle:@"镜像" target:self action:@selector(toggleMirror:)];
    mirror.frame = NSMakeRect(148, 12, 70, 22);
    mirror.state = NSControlStateValueOn;
    mirror.contentTintColor = [NSColor whiteColor];
    [bar addSubview:mirror];

    self.status = [[NSTextField alloc] initWithFrame:NSMakeRect(230, 12, 400, 20)];
    self.status.editable = NO; self.status.bordered = NO; self.status.drawsBackground = NO;
    self.status.selectable = NO;
    self.status.textColor = [NSColor colorWithWhite:0.8 alpha:1];
    self.status.font = [NSFont systemFontOfSize:12];
    self.status.stringValue = @"";
    self.status.autoresizingMask = NSViewWidthSizable;
    [bar addSubview:self.status];

    [content addSubview:bar];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    /* 启动采集 */
    self.cap = [[Capture alloc] init];
    self.cap.view = self.view;
    __block NSString *err = nil;
    LOG(@"把采集启动推迟到窗口就绪后");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self requestPermissionThenStart];
    });

    /* 看门狗：3.5 秒仍未出帧，重启一次会话 */
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (![weakSelf.view hasImage]) {
            LOG(@"⚠️ 6 秒无帧，重启会话");
            [weakSelf.cap.session stopRunning];
            [NSThread sleepForTimeInterval:1.0];
            [weakSelf.cap.session startRunning];
            LOG(@"重启完成，running=%d", weakSelf.cap.session.isRunning);
        } else {
            LOG(@"✅ 已出帧，无需重启");
        }
    });

    /* 空格键拍照 */
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
        if (e.keyCode == 49) { [self snapshot:nil]; return nil; }
        return e;
    }];
}

- (void)toggleMirror:(NSButton *)sender {
    self.view.mirror = (sender.state == NSControlStateValueOn);
    [self.view setNeedsDisplay:YES];
}

- (void)snapshot:(id)sender {
    CGImageRef img = [self.view copyCurrentImage];
    if (!img) { self.status.stringValue = @"尚未收到画面，稍等一秒再试"; return; }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:img];
    CGImageRelease(img);
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *name = [NSString stringWithFormat:@"camera-%@.png", [df stringFromDate:[NSDate date]]];
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:[@"Desktop/" stringByAppendingString:name]];
    if ([png writeToFile:path atomically:YES]) {
        self.status.stringValue = [NSString stringWithFormat:@"已保存 %@ (%dx%d, %.1f MB)",
                                   name, (int)rep.pixelsWide, (int)rep.pixelsHigh, png.length / 1048576.0];
    } else {
        self.status.stringValue = @"保存失败";
    }
}

- (void)requestPermissionThenStart {
    AVAuthorizationStatus st = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    LOG(@"授权状态 = %ld (0=未决 2=已拒 3=已允许)", (long)st);
    if (st == AVAuthorizationStatusAuthorized) {
        [self.cap startWithError:nil];
        return;
    }
    self.status.stringValue = @"等待摄像头授权…（如弹出对话框请点“允许”）";
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        LOG(@"授权回调 granted=%d", granted);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) {
                self.status.stringValue = @"已授权，正在启动";
                [self.cap startWithError:nil];
            } else {
                self.status.stringValue = @"授权被拒绝 — 请到 系统设置 → 隐私与安全性 → 摄像头 勾选本程序";
                NSAlert *a = [[NSAlert alloc] init];
                a.messageText = @"摄像头权限被拒绝";
                a.informativeText = @"请打开 系统设置 → 隐私与安全性 → 摄像头，勾选「摄像头预览」，然后重新打开本程序。";
                [a addButtonWithTitle:@"打开设置"];
                [a addButtonWithTitle:@"稍后"];
                if ([a runModal] == NSAlertFirstButtonReturn) {
                    [[NSWorkspace sharedWorkspace] openURL:
                     [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"]];
                }
            }
        });
    }];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }

- (void)applicationWillTerminate:(NSNotification *)note {
    [self.cap stop];
}

@end


int main(int argc, const char *argv[]) {
    @autoreleasepool {
        LOG(@"=== main 进入 ===");
        NSApplication *app = [NSApplication sharedApplication];
        Controller *ctl = [[Controller alloc] init];
        app.delegate = ctl;
        [app run];
    }
    return 0;
}

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

static NSString *strProp(AudioDeviceID d, AudioObjectPropertySelector sel,
                         AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress a = { sel, scope, kAudioObjectPropertyElementMain };
    CFStringRef s = NULL;
    UInt32 sz = sizeof(s);
    if (AudioObjectGetPropertyData(d, &a, 0, NULL, &sz, &s) != noErr || s == NULL) return @"";
    return (__bridge_transfer NSString *)s;
}

static UInt32 outChannels(AudioDeviceID d) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyStreamConfiguration,
                                     kAudioObjectPropertyScopeOutput,
                                     kAudioObjectPropertyElementMain };
    UInt32 sz = 0;
    if (AudioObjectGetPropertyDataSize(d, &a, 0, NULL, &sz) != noErr || sz == 0) return 0;
    AudioBufferList *bl = (AudioBufferList *)malloc(sz);
    if (!bl) return 0;
    UInt32 ch = 0;
    if (AudioObjectGetPropertyData(d, &a, 0, NULL, &sz, bl) == noErr) {
        for (UInt32 i = 0; i < bl->mNumberBuffers; i++) ch += bl->mBuffers[i].mNumberChannels;
    }
    free(bl);
    return ch;
}

static NSArray<NSNumber *> *allDevices(void) {
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDevices,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain };
    UInt32 sz = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &sz) != noErr || sz == 0) return @[];
    AudioDeviceID *buf = (AudioDeviceID *)malloc(sz);
    if (!buf) return @[];
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, buf) != noErr) {
        free(buf);
        return @[];
    }
    NSMutableArray *r = [NSMutableArray array];
    UInt32 n = sz / sizeof(AudioDeviceID);
    for (UInt32 i = 0; i < n; i++) [r addObject:@(buf[i])];
    free(buf);
    return r;
}

static AudioObjectPropertyAddress defaultAddr(BOOL sys) {
    AudioObjectPropertyAddress a = {
        sys ? kAudioHardwarePropertyDefaultSystemOutputDevice : kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    return a;
}

static AudioDeviceID defaultDev(BOOL sys) {
    AudioObjectPropertyAddress a = defaultAddr(sys);
    AudioDeviceID d = kAudioObjectUnknown;
    UInt32 sz = sizeof(d);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, &d) != noErr)
        return kAudioObjectUnknown;
    return d;
}

static BOOL setDefault(AudioDeviceID d, BOOL sys) {
    AudioObjectPropertyAddress a = defaultAddr(sys);
    return AudioObjectSetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, sizeof(d), &d) == noErr;
}

static NSArray<NSDictionary *> *listOutputs(void) {
    NSArray<NSNumber *> *devs = allDevices();
    AudioDeviceID cur = defaultDev(NO), curSys = defaultDev(YES);
    NSMutableArray *outs = [NSMutableArray array];
    NSInteger idx = 0;
    printf("=== 可用输出设备 ===\n");
    for (NSNumber *num in devs) {
        AudioDeviceID d = (AudioDeviceID)[num unsignedIntValue];
        UInt32 ch = outChannels(d);
        if (ch == 0) continue;
        NSString *name = strProp(d, kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal);
        NSString *uid  = strProp(d, kAudioDevicePropertyDeviceUID, kAudioObjectPropertyScopeGlobal);
        idx++;
        NSString *line = [NSString stringWithFormat:
            @"  #%ld  id=%u  ch=%u  %@%@%@\n      uid=%@",
            (long)idx, (unsigned)d, (unsigned)ch, name,
            (d == cur    ? @"  ← 默认输出" : @""),
            (d == curSys ? @"  ← 系统输出" : @""), uid];
        printf("%s\n", [line UTF8String]);
        [outs addObject:@{@"id": @(d), @"name": name, @"uid": uid, @"idx": @(idx)}];
    }
    if (idx == 0) printf("  (没有输出设备)\n");
    return outs;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"list";
        NSArray<NSDictionary *> *outs = listOutputs();

        if ([mode isEqualToString:@"list"]) return 0;
        if ([mode isEqualToString:@"guard"]) {
            AudioDeviceID cur = defaultDev(NO);
            NSString *curName = strProp(cur, kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal);
            BOOL isNV  = [curName rangeOfString:@"NVIDIA" options:NSCaseInsensitiveSearch].location != NSNotFound;
            BOOL isALC = [curName rangeOfString:@"ALC662" options:NSCaseInsensitiveSearch].location != NSNotFound;
            if (isALC && !isNV) {
                printf("\nguard: 默认输出已是 %s，无需切换\n", [curName UTF8String]);
                return 0;
            }
            mode = @"auto";
        }
        if (![mode isEqualToString:@"auto"] && ![mode isEqualToString:@"set"]) {
            printf("用法: setoutput list | auto | guard | set <序号|uid|名称片段>\n");
            return 1;
        }

        NSDictionary *pick = nil;
        if ([mode isEqualToString:@"auto"]) {
            for (NSDictionary *o in outs) {
                NSString *n = o[@"name"];
                BOOL isALC = [n rangeOfString:@"ALC662" options:NSCaseInsensitiveSearch].location != NSNotFound;
                BOOL isHDMI = [n rangeOfString:@"HDMI" options:NSCaseInsensitiveSearch].location != NSNotFound;
                if (isALC && !isHDMI) { pick = o; break; }
            }
            if (!pick) {
                for (NSDictionary *o in outs) {
                    NSString *n = o[@"name"];
                    BOOL isNV = [n rangeOfString:@"NVIDIA" options:NSCaseInsensitiveSearch].location != NSNotFound;
                    BOOL isHDMI = [n rangeOfString:@"HDMI" options:NSCaseInsensitiveSearch].location != NSNotFound;
                    if (!isNV && !isHDMI) { pick = o; break; }
                }
            }
        } else {
            if (argc < 3) { printf("❌ set 需要参数\n"); return 1; }
            NSString *arg = [NSString stringWithUTF8String:argv[2]];
            for (NSDictionary *o in outs) {
                if ([o[@"uid"] isEqualToString:arg] ||
                    [[o[@"idx"] stringValue] isEqualToString:arg] ||
                    [o[@"name"] rangeOfString:arg options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    pick = o;
                    break;
                }
            }
        }

        if (!pick) { printf("❌ 没找到目标输出设备\n"); return 1; }
        AudioDeviceID d = (AudioDeviceID)[pick[@"id"] unsignedIntValue];
        BOOL ok1 = setDefault(d, NO);
        BOOL ok2 = setDefault(d, YES);
        printf("\n→ 目标: %s (id=%u)\n", [pick[@"name"] UTF8String], (unsigned)d);
        printf("  设置默认输出: %s   设置系统输出: %s\n", ok1 ? "OK" : "失败", ok2 ? "OK" : "失败");
        AudioDeviceID back = defaultDev(NO);
        printf("  回读验证: %s\n", (back == d ? "✅ 已生效" : "❌ 未生效（可能被系统改回）"));
        return (ok1 && back == d) ? 0 : 1;
    }
}

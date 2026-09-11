#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

extern char *ramlet_snapshot_tsv(void);
extern void ramlet_string_free(char *value);

static const NSInteger kMaximumVisibleApps = 18;
static const CGFloat kStatusItemWidth = 92.0;
static NSString *const kIncludeUnattributedDefaultsKey = @"includeUnattributedMemory";

static NSBundle *RamletStringsBundle(void) {
    static NSBundle *bundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *main = NSBundle.mainBundle;
        if ([main pathForResource:@"Localizable" ofType:@"strings"] != nil) {
            bundle = main;
            return;
        }
#ifdef RAMLET_DEV_RESOURCES
        NSBundle *devBundle = [NSBundle bundleWithPath:@RAMLET_DEV_RESOURCES];
        if (devBundle != nil && [devBundle pathForResource:@"Localizable" ofType:@"strings"] != nil) {
            bundle = devBundle;
            return;
        }
#endif
        bundle = main;
    });
    return bundle;
}

static NSString *RamletLocalizedString(NSString *key) {
    return [RamletStringsBundle() localizedStringForKey:key value:key table:nil];
}

@interface RamletAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenu *menu;
@property(nonatomic, strong) NSTimer *timer;
@end

@implementation RamletAppDelegate

- (NSArray<NSArray<NSString *> *> *)snapshotRows {
    char *raw = ramlet_snapshot_tsv();
    if (raw == NULL) {
        return @[];
    }

    NSString *payload = [NSString stringWithUTF8String:raw];
    ramlet_string_free(raw);
    if (payload == nil) {
        return @[];
    }

    NSMutableArray<NSArray<NSString *> *> *rows = [NSMutableArray array];
    for (NSString *line in [payload componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (line.length > 0) {
            [rows addObject:[line componentsSeparatedByString:@"\t"]];
        }
    }
    return rows;
}

- (NSString *)memoryString:(unsigned long long)bytes {
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes
                                          countStyle:NSByteCountFormatterCountStyleMemory];
}

- (NSImage *)symbol:(NSString *)name description:(NSString *)description {
    NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:description];
    if (image != nil) {
        image.template = YES;
        image = [image imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithPointSize:13.0
                                                             weight:NSFontWeightMedium]];
    }
    return image;
}

- (NSMenuItem *)informationalItem:(NSString *)title {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    item.enabled = NO;
    return item;
}

- (NSStatusItem *)createStatusItem {
    NSStatusItem *item = [[NSStatusBar systemStatusBar] statusItemWithLength:kStatusItemWidth];
    item.button.image = [self symbol:@"memorychip" description:@"Ramlet"];
    item.button.imagePosition = NSImageLeft;
    item.button.font = [NSFont monospacedDigitSystemFontOfSize:13.0 weight:NSFontWeightRegular];
    return item;
}

- (BOOL)includeUnattributedMemory {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:kIncludeUnattributedDefaultsKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kIncludeUnattributedDefaultsKey];
}

- (unsigned long long)displayedBytesFromMeta:(NSArray<NSString *> *)meta {
    unsigned long long used = strtoull(meta[1].UTF8String, NULL, 10);
    if ([self includeUnattributedMemory]) {
        return used;
    }

    unsigned long long total = strtoull(meta[2].UTF8String, NULL, 10);
    unsigned long long appFootprint = strtoull(meta[6].UTF8String, NULL, 10);
    unsigned long long services = strtoull(meta[7].UTF8String, NULL, 10);
    return MIN(appFootprint + services, total);
}

- (void)updateStatusFromRows:(NSArray<NSArray<NSString *> *> *)rows {
    if (rows.count == 0 || rows.firstObject.count < 8) {
        self.statusItem.button.title = @" —";
        self.statusItem.button.toolTip = RamletLocalizedString(@"Ramlet — measurement unavailable");
        return;
    }

    NSArray<NSString *> *meta = rows.firstObject;
    unsigned long long used = strtoull(meta[1].UTF8String, NULL, 10);
    unsigned long long total = strtoull(meta[2].UTF8String, NULL, 10);
    unsigned long long displayed = [self displayedBytesFromMeta:meta];
    NSString *displayedText = [self memoryString:displayed];
    NSString *totalText = [self memoryString:total];
    self.statusItem.button.title = [NSString stringWithFormat:@" %@", displayedText];
    if ([self includeUnattributedMemory]) {
        self.statusItem.button.toolTip = [NSString stringWithFormat:
            RamletLocalizedString(@"Ramlet — %@ used of %@ unified memory"),
            displayedText,
            totalText];
    } else {
        self.statusItem.button.toolTip = [NSString stringWithFormat:
            RamletLocalizedString(@"Ramlet — %@ attributed to apps and services of %@ (%@ used in total)"),
            displayedText,
            totalText,
            [self memoryString:used]];
    }
}

- (void)refreshStatus:(NSTimer *)timer {
    (void)timer;
    [self updateStatusFromRows:[self snapshotRows]];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    NSArray<NSArray<NSString *> *> *rows = [self snapshotRows];
    [self updateStatusFromRows:rows];
    [menu removeAllItems];

    if (rows.count == 0 || rows.firstObject.count < 10) {
        [menu addItem:[self informationalItem:RamletLocalizedString(@"Memory measurement unavailable")]];
        [menu addItem:NSMenuItem.separatorItem];
        [self addActionsToMenu:menu];
        return;
    }

    NSArray<NSString *> *meta = rows.firstObject;
    unsigned long long used = strtoull(meta[1].UTF8String, NULL, 10);
    unsigned long long total = strtoull(meta[2].UTF8String, NULL, 10);
    unsigned long long compressed = strtoull(meta[3].UTF8String, NULL, 10);
    unsigned long long wired = strtoull(meta[4].UTF8String, NULL, 10);
    unsigned long long swap = strtoull(meta[5].UTF8String, NULL, 10);
    unsigned long long appFootprintBytes = strtoull(meta[6].UTF8String, NULL, 10);
    unsigned long long serviceBytes = strtoull(meta[7].UTF8String, NULL, 10);

    BOOL includesUnattributed = [self includeUnattributedMemory];
    unsigned long long displayed = [self displayedBytesFromMeta:meta];
    NSString *summaryLabel = includesUnattributed
        ? RamletLocalizedString(@"used")
        : RamletLocalizedString(@"attributed");
    NSMenuItem *summary = [self informationalItem:[NSString stringWithFormat:
        RamletLocalizedString(@"%@ %@ of %@"),
        [self memoryString:displayed],
        summaryLabel,
        [self memoryString:total]]];
    summary.image = [self symbol:@"memorychip.fill" description:RamletLocalizedString(@"Unified memory")];
    [menu addItem:summary];
    [menu addItem:[self informationalItem:[NSString stringWithFormat:
        RamletLocalizedString(@"Compressed %@  ·  Wired %@  ·  Swap %@"),
        [self memoryString:compressed],
        [self memoryString:wired],
        [self memoryString:swap]]]];
    [menu addItem:NSMenuItem.separatorItem];

    NSInteger visibleApps = 0;
    unsigned long long hiddenAppBytes = 0;
    NSInteger hiddenAppCount = 0;
    for (NSUInteger index = 1; index < rows.count; index++) {
        NSArray<NSString *> *row = rows[index];
        if (row.count < 5 || ![row[0] isEqualToString:@"APP"]) {
            continue;
        }

        unsigned long long bytes = strtoull(row[1].UTF8String, NULL, 10);
        if (bytes < 16ULL * 1024ULL * 1024ULL) {
            hiddenAppBytes += bytes;
            hiddenAppCount += 1;
            continue;
        }
        if (visibleApps >= kMaximumVisibleApps) {
            hiddenAppBytes += bytes;
            hiddenAppCount += 1;
            continue;
        }

        NSString *bundlePath = row[3];
        NSString *name = row[4];
        NSString *title = [NSString stringWithFormat:@"%@  ·  %@", name, [self memoryString:bytes]];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        item.enabled = YES;
        NSInteger processCount = (NSInteger)strtoll(row[2].UTF8String, NULL, 10);
        NSString *processFormat = processCount == 1
            ? RamletLocalizedString(@"%ld aggregated process")
            : RamletLocalizedString(@"%ld aggregated processes");
        item.toolTip = [NSString stringWithFormat:processFormat, (long)processCount];

        NSImage *icon = [[[NSWorkspace sharedWorkspace] iconForFile:bundlePath] copy];
        icon.size = NSMakeSize(18.0, 18.0);
        item.image = icon;
        [menu addItem:item];
        visibleApps += 1;
    }

    if (hiddenAppCount > 0) {
        NSString *otherFormat = hiddenAppCount == 1
            ? RamletLocalizedString(@"%ld other application  ·  %@")
            : RamletLocalizedString(@"%ld other applications  ·  %@");
        NSMenuItem *otherApps = [self informationalItem:[NSString stringWithFormat:
            otherFormat,
            (long)hiddenAppCount,
            [self memoryString:hiddenAppBytes]]];
        otherApps.image = [self symbol:@"square.stack.3d.up.fill" description:RamletLocalizedString(@"Other applications")];
        [menu addItem:otherApps];
    }

    NSMenuItem *services = [self informationalItem:[NSString stringWithFormat:
        RamletLocalizedString(@"macOS and services  ·  %@"), [self memoryString:serviceBytes]]];
    services.image = [self symbol:@"gearshape.2.fill" description:RamletLocalizedString(@"System services")];
    [menu addItem:services];

    unsigned long long attributedBytes = appFootprintBytes + serviceBytes;
    unsigned long long unattributedBytes = used > attributedBytes ? used - attributedBytes : 0;
    NSMenuItem *unattributed = [self informationalItem:[NSString stringWithFormat:
        RamletLocalizedString(@"Caches and unattributed memory  ·  ≈ %@"),
        [self memoryString:unattributedBytes]]];
    unattributed.image = [self symbol:@"internaldrive.fill"
                          description:RamletLocalizedString(@"Caches and unattributed memory")];
    unattributed.toolTip = RamletLocalizedString(@"File cache, shared memory, GPU, and allocations that macOS does not cleanly attach to an application.");
    [menu addItem:unattributed];

    NSMenuItem *cacheToggle = [[NSMenuItem alloc] initWithTitle:RamletLocalizedString(@"Include caches and unattributed memory")
                                                        action:@selector(toggleUnattributedMemory:)
                                                 keyEquivalent:@""];
    cacheToggle.target = self;
    cacheToggle.enabled = YES;
    cacheToggle.state = includesUnattributed ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:cacheToggle];

    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *note = [self informationalItem:RamletLocalizedString(@"Physical footprint per app · GPU included when attributable")];
    note.toolTip = RamletLocalizedString(@"macOS does not publish a complete breakdown of unified GPU memory per application.");
    [menu addItem:note];
    [menu addItem:NSMenuItem.separatorItem];
    [self addActionsToMenu:menu];
}

- (void)addActionsToMenu:(NSMenu *)menu {
    NSMenuItem *refresh = [[NSMenuItem alloc] initWithTitle:RamletLocalizedString(@"Refresh Now")
                                                    action:@selector(refreshNow:)
                                             keyEquivalent:@"r"];
    refresh.target = self;
    refresh.image = [self symbol:@"arrow.clockwise" description:RamletLocalizedString(@"Refresh")];
    [menu addItem:refresh];

    NSMenuItem *activity = [[NSMenuItem alloc] initWithTitle:RamletLocalizedString(@"Open Activity Monitor")
                                                     action:@selector(openActivityMonitor:)
                                              keyEquivalent:@""];
    activity.target = self;
    activity.image = [self symbol:@"waveform.path.ecg.rectangle" description:RamletLocalizedString(@"Activity Monitor")];
    [menu addItem:activity];

    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:RamletLocalizedString(@"Quit Ramlet")
                                                 action:@selector(quit:)
                                          keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];
}

- (void)refreshNow:(id)sender {
    (void)sender;
    [self updateStatusFromRows:[self snapshotRows]];
}

- (void)toggleUnattributedMemory:(NSMenuItem *)sender {
    BOOL nextValue = ![self includeUnattributedMemory];
    [NSUserDefaults.standardUserDefaults setBool:nextValue
                                          forKey:kIncludeUnattributedDefaultsKey];
    sender.state = nextValue ? NSControlStateValueOn : NSControlStateValueOff;
    [self refreshStatus:nil];
}

- (void)openActivityMonitor:(id)sender {
    (void)sender;
    NSURL *url = [NSURL fileURLWithPath:@"/System/Applications/Utilities/Activity Monitor.app"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)quit:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.statusItem = [self createStatusItem];

    self.menu = [[NSMenu alloc] initWithTitle:@"Ramlet"];
    self.menu.autoenablesItems = NO;
    self.menu.delegate = self;
    self.statusItem.menu = self.menu;

    [self refreshStatus:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:15.0
                                                  target:self
                                                selector:@selector(refreshStatus:)
                                                userInfo:nil
                                                 repeats:YES];

    if ([NSProcessInfo.processInfo.arguments containsObject:@"--open-menu"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            [self.statusItem popUpStatusItemMenu:self.menu];
#pragma clang diagnostic pop
        });
    }
}

@end

static RamletAppDelegate *delegate;

int ramlet_run(void) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        delegate = [[RamletAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}

int ramlet_ui_self_test(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        id previousPreference = [defaults objectForKey:kIncludeUnattributedDefaultsKey];
        [defaults setBool:YES forKey:kIncludeUnattributedDefaultsKey];

        RamletAppDelegate *tester = [[RamletAppDelegate alloc] init];
        tester.statusItem = [tester createStatusItem];
        tester.menu = [[NSMenu alloc] initWithTitle:@"Ramlet"];
        tester.menu.autoenablesItems = NO;
        [tester refreshStatus:nil];
        [tester menuNeedsUpdate:tester.menu];

        BOOL hasSummary = NO;
        BOOL hasApplicationWithIcon = NO;
        BOOL hasCacheToggle = NO;
        NSMenuItem *cacheToggleItem = nil;
        BOOL hasRefresh = NO;
        BOOL hasQuit = NO;
        NSString *usedWord = RamletLocalizedString(@"used");
        NSString *cacheToggleTitle = RamletLocalizedString(@"Include caches and unattributed memory");
        NSString *refreshTitle = RamletLocalizedString(@"Refresh Now");
        NSString *quitTitle = RamletLocalizedString(@"Quit Ramlet");
        for (NSMenuItem *item in tester.menu.itemArray) {
            if ([item.title containsString:usedWord]) {
                hasSummary = YES;
            }
            if ([item.title containsString:@"  ·  "] && item.image != nil) {
                hasApplicationWithIcon = YES;
            }
            if ([item.title isEqualToString:cacheToggleTitle]) {
                hasCacheToggle = YES;
                cacheToggleItem = item;
            }
            if ([item.title isEqualToString:refreshTitle]) {
                hasRefresh = YES;
            }
            if ([item.title isEqualToString:quitTitle]) {
                hasQuit = YES;
            }
        }

        BOOL hasStatus = tester.statusItem.button.image != nil && tester.statusItem.button.title.length > 0;
        NSImage *expectedOutlineIcon = [tester symbol:@"memorychip" description:@"Ramlet"];
        NSData *actualIconData = tester.statusItem.button.image.TIFFRepresentation;
        NSData *expectedIconData = expectedOutlineIcon.TIFFRepresentation;
        BOOL hasOutlineStatusIcon = actualIconData != nil &&
                                    expectedIconData != nil &&
                                    [actualIconData isEqualToData:expectedIconData];
        CGFloat originalWidth = tester.statusItem.length;
        tester.statusItem.button.title = @" 8 Go";
        CGFloat shortValueWidth = tester.statusItem.length;
        tester.statusItem.button.title = @" 47,9 Go";
        CGFloat longValueWidth = tester.statusItem.length;
        BOOL hasFixedStatusWidth = originalWidth == kStatusItemWidth &&
                                   shortValueWidth == kStatusItemWidth &&
                                   longValueWidth == kStatusItemWidth;

        BOOL toggleActionSent = cacheToggleItem != nil &&
                                cacheToggleItem.action != NULL &&
                                [NSApp sendAction:cacheToggleItem.action
                                               to:cacheToggleItem.target
                                             from:cacheToggleItem];
        unsigned long long gibibyte = 1024ULL * 1024ULL * 1024ULL;
        NSArray<NSArray<NSString *> *> *fixtureRows = @[@[
            @"META",
            [NSString stringWithFormat:@"%llu", 40ULL * gibibyte],
            [NSString stringWithFormat:@"%llu", 48ULL * gibibyte],
            @"0",
            @"0",
            @"0",
            [NSString stringWithFormat:@"%llu", 20ULL * gibibyte],
            [NSString stringWithFormat:@"%llu", 5ULL * gibibyte],
            @"3",
            @"0"
        ]];
        [tester updateStatusFromRows:fixtureRows];
        NSString *attributedTitle = [NSString stringWithFormat:
            @" %@", [tester memoryString:25ULL * gibibyte]];
        BOOL toggleExcludesUnattributed = toggleActionSent &&
                                          ![defaults boolForKey:kIncludeUnattributedDefaultsKey] &&
                                          cacheToggleItem.state == NSControlStateValueOff &&
                                          [tester.statusItem.button.title isEqualToString:attributedTitle] &&
                                          [tester.statusItem.button.toolTip containsString:RamletLocalizedString(@"attributed")];

        [[NSStatusBar systemStatusBar] removeStatusItem:tester.statusItem];
        if (previousPreference != nil) {
            [defaults setObject:previousPreference forKey:kIncludeUnattributedDefaultsKey];
        } else {
            [defaults removeObjectForKey:kIncludeUnattributedDefaultsKey];
        }
        return (hasStatus && hasOutlineStatusIcon && hasFixedStatusWidth && hasSummary && hasApplicationWithIcon && hasCacheToggle && toggleExcludesUnattributed && hasRefresh && hasQuit) ? 0 : 1;
    }
}

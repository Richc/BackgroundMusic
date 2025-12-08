//
//  BGMDeviceWrapper.m
//  Manatee
//
//  Objective-C wrapper for BGMDevice C++ class
//

#import "Manatee-Bridging-Header.h"
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import <objc/runtime.h>

// Constants
NSString * const kManateeAudioClientsChangedNotification = @"ManateeAudioClientsChangedNotification";
NSString * const kManateeDeviceListChangedNotification = @"ManateeDeviceListChangedNotification";
NSString * const kManateeVolumeChangedNotification = @"ManateeVolumeChangedNotification";

// MARK: - BGMDeviceWrapper Implementation

@interface BGMDeviceWrapper ()
@property (nonatomic, assign) AudioObjectID deviceID;
@property (nonatomic, copy) void (^volumeChangeCallback)(NSString *, float);
@property (nonatomic, copy) void (^muteChangeCallback)(NSString *, BOOL);
@property (nonatomic, copy) void (^clientChangeCallback)(void);
@end

@implementation BGMDeviceWrapper

static BGMDeviceWrapper *sharedInstance = nil;

+ (instancetype)sharedDevice {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[BGMDeviceWrapper alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _deviceID = kAudioObjectUnknown;
    }
    return self;
}

- (BOOL)isAvailable {
    return self.deviceID != kAudioObjectUnknown;
}

- (NSString *)outputDeviceUID {
    // TODO: Implement using BGMDevice::CopyOutputDeviceUID()
    return nil;
}

- (BOOL)connect {
    // Find BGMDevice by searching for device with specific UID
    AudioObjectPropertyAddress propertyAddress = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 dataSize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(
        kAudioObjectSystemObject,
        &propertyAddress,
        0,
        NULL,
        &dataSize
    );
    
    if (status != noErr) {
        NSLog(@"[Manatee] Failed to get device list size: %d", (int)status);
        return NO;
    }
    
    UInt32 deviceCount = dataSize / sizeof(AudioDeviceID);
    AudioDeviceID *devices = (AudioDeviceID *)malloc(dataSize);
    
    status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &propertyAddress,
        0,
        NULL,
        &dataSize,
        devices
    );
    
    if (status != noErr) {
        NSLog(@"[Manatee] Failed to get device list: %d", (int)status);
        free(devices);
        return NO;
    }
    
    // Search for BGMDevice
    for (UInt32 i = 0; i < deviceCount; i++) {
        CFStringRef uidRef = NULL;
        dataSize = sizeof(CFStringRef);
        propertyAddress.mSelector = kAudioDevicePropertyDeviceUID;
        
        status = AudioObjectGetPropertyData(
            devices[i],
            &propertyAddress,
            0,
            NULL,
            &dataSize,
            &uidRef
        );
        
        if (status == noErr && uidRef != NULL) {
            NSString *uid = (__bridge_transfer NSString *)uidRef;
            // Check for BGMDevice or Manatee device UID
            if ([uid containsString:@"BGMDevice"] || 
                [uid containsString:@"ManateeDevice"] ||
                [uid containsString:@"Background Music"]) {
                self.deviceID = devices[i];
                NSLog(@"[Manatee] Connected to virtual device: %@ (ID: %u)", uid, devices[i]);
                free(devices);
                return YES;
            }
        }
    }
    
    free(devices);
    NSLog(@"[Manatee] Virtual audio device not found");
    return NO;
}

- (void)disconnect {
    self.deviceID = kAudioObjectUnknown;
}

- (BOOL)setOutputDeviceWithUID:(NSString *)uid {
    if (!self.isAvailable) return NO;
    
    // TODO: Implement using BGMDevice::SetOutputDeviceWithUID()
    // This requires the C++ BGMDevice class
    
    return YES;
}

- (float)volumeForAppWithBundleID:(NSString *)bundleID {
    if (!self.isAvailable) return 1.0;
    
    // TODO: Implement using BGMDevice app volume controls
    // For now, return default volume
    return 1.0;
}

- (BOOL)setVolume:(float)volume forAppWithBundleID:(NSString *)bundleID {
    if (!self.isAvailable) return NO;
    
    // TODO: Implement using BGMDevice::SetAppVolume()
    NSLog(@"[Manatee] Set volume %.2f for %@", volume, bundleID);
    
    // Notify callback
    if (self.volumeChangeCallback) {
        self.volumeChangeCallback(bundleID, volume);
    }
    
    return YES;
}

- (BOOL)isMutedAppWithBundleID:(NSString *)bundleID {
    if (!self.isAvailable) return NO;
    
    // TODO: Implement
    return NO;
}

- (BOOL)setMuted:(BOOL)muted forAppWithBundleID:(NSString *)bundleID {
    if (!self.isAvailable) return NO;
    
    // TODO: Implement
    NSLog(@"[Manatee] Set muted %d for %@", muted, bundleID);
    
    if (self.muteChangeCallback) {
        self.muteChangeCallback(bundleID, muted);
    }
    
    return YES;
}

- (float)panForAppWithBundleID:(NSString *)bundleID {
    return 0.0; // Center
}

- (BOOL)setPan:(float)pan forAppWithBundleID:(NSString *)bundleID {
    if (!self.isAvailable) return NO;
    
    // TODO: Implement
    NSLog(@"[Manatee] Set pan %.2f for %@", pan, bundleID);
    return YES;
}

- (NSArray<NSDictionary *> *)activeAudioClients {
    NSMutableArray *clients = [NSMutableArray array];
    
    // Get running applications that can produce audio
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSArray<NSRunningApplication *> *runningApps = workspace.runningApplications;
    
    for (NSRunningApplication *app in runningApps) {
        // Skip background apps and system processes
        if (app.activationPolicy != NSApplicationActivationPolicyRegular) {
            continue;
        }
        
        if (app.bundleIdentifier) {
            NSDictionary *clientInfo = @{
                @"bundleID": app.bundleIdentifier,
                @"name": app.localizedName ?: @"Unknown",
                @"pid": @(app.processIdentifier),
                @"icon": app.icon ?: [NSImage imageNamed:NSImageNameApplicationIcon]
            };
            [clients addObject:clientInfo];
        }
    }
    
    return [clients copy];
}

- (void)registerVolumeChangeCallback:(void (^)(NSString *, float))callback {
    self.volumeChangeCallback = callback;
}

- (void)registerMuteChangeCallback:(void (^)(NSString *, BOOL))callback {
    self.muteChangeCallback = callback;
}

- (void)registerClientChangeCallback:(void (^)(void))callback {
    self.clientChangeCallback = callback;
    
    // Register for workspace notifications
    [[[NSWorkspace sharedWorkspace] notificationCenter] 
        addObserverForName:NSWorkspaceDidLaunchApplicationNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            if (callback) callback();
        }];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter]
        addObserverForName:NSWorkspaceDidTerminateApplicationNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            if (callback) callback();
        }];
}

@end


// MARK: - AudioDeviceUtilities Implementation

@implementation AudioDeviceUtilities

+ (NSArray<NSDictionary *> *)allOutputDevices {
    return [self devicesForScope:kAudioDevicePropertyScopeOutput];
}

+ (NSArray<NSDictionary *> *)allInputDevices {
    return [self devicesForScope:kAudioDevicePropertyScopeInput];
}

+ (NSArray<NSDictionary *> *)devicesForScope:(AudioObjectPropertyScope)scope {
    NSMutableArray *result = [NSMutableArray array];
    
    AudioObjectPropertyAddress propertyAddress = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 dataSize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(
        kAudioObjectSystemObject,
        &propertyAddress,
        0,
        NULL,
        &dataSize
    );
    
    if (status != noErr) return @[];
    
    UInt32 deviceCount = dataSize / sizeof(AudioDeviceID);
    AudioDeviceID *devices = (AudioDeviceID *)malloc(dataSize);
    
    status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &propertyAddress,
        0,
        NULL,
        &dataSize,
        devices
    );
    
    if (status != noErr) {
        free(devices);
        return @[];
    }
    
    for (UInt32 i = 0; i < deviceCount; i++) {
        // Check if device has channels for this scope
        UInt32 channels = [self channelCountForDeviceID:devices[i] 
                                                isInput:(scope == kAudioDevicePropertyScopeInput)];
        if (channels == 0) continue;
        
        NSString *name = [self deviceNameForID:devices[i]];
        NSString *uid = [self deviceUIDForID:devices[i]];
        Float64 sampleRate = [self sampleRateForDeviceID:devices[i]];
        
        if (name && uid) {
            [result addObject:@{
                @"id": @(devices[i]),
                @"name": name,
                @"uid": uid,
                @"sampleRate": @(sampleRate),
                @"channels": @(channels)
            }];
        }
    }
    
    free(devices);
    return [result copy];
}

+ (NSDictionary *)defaultOutputDevice {
    AudioObjectPropertyAddress propertyAddress = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    AudioDeviceID deviceID;
    UInt32 dataSize = sizeof(AudioDeviceID);
    
    OSStatus status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &propertyAddress,
        0,
        NULL,
        &dataSize,
        &deviceID
    );
    
    if (status != noErr) return nil;
    
    NSString *name = [self deviceNameForID:deviceID];
    NSString *uid = [self deviceUIDForID:deviceID];
    
    if (name && uid) {
        return @{
            @"id": @(deviceID),
            @"name": name,
            @"uid": uid,
            @"sampleRate": @([self sampleRateForDeviceID:deviceID]),
            @"channels": @([self channelCountForDeviceID:deviceID isInput:NO])
        };
    }
    
    return nil;
}

+ (NSDictionary *)defaultInputDevice {
    AudioObjectPropertyAddress propertyAddress = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    AudioDeviceID deviceID;
    UInt32 dataSize = sizeof(AudioDeviceID);
    
    OSStatus status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &propertyAddress,
        0,
        NULL,
        &dataSize,
        &deviceID
    );
    
    if (status != noErr) return nil;
    
    NSString *name = [self deviceNameForID:deviceID];
    NSString *uid = [self deviceUIDForID:deviceID];
    
    if (name && uid) {
        return @{
            @"id": @(deviceID),
            @"name": name,
            @"uid": uid,
            @"sampleRate": @([self sampleRateForDeviceID:deviceID]),
            @"channels": @([self channelCountForDeviceID:deviceID isInput:YES])
        };
    }
    
    return nil;
}

+ (BOOL)setDefaultOutputDeviceWithUID:(NSString *)uid {
    // Find device by UID
    NSArray *devices = [self allOutputDevices];
    
    for (NSDictionary *device in devices) {
        if ([device[@"uid"] isEqualToString:uid]) {
            AudioDeviceID deviceID = [device[@"id"] unsignedIntValue];
            
            AudioObjectPropertyAddress propertyAddress = {
                kAudioHardwarePropertyDefaultOutputDevice,
                kAudioObjectPropertyScopeGlobal,
                kAudioObjectPropertyElementMain
            };
            
            OSStatus status = AudioObjectSetPropertyData(
                kAudioObjectSystemObject,
                &propertyAddress,
                0,
                NULL,
                sizeof(AudioDeviceID),
                &deviceID
            );
            
            return status == noErr;
        }
    }
    
    return NO;
}

+ (NSString *)deviceNameForID:(AudioObjectID)deviceID {
    AudioObjectPropertyAddress propertyAddress = {
        kAudioDevicePropertyDeviceNameCFString,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    CFStringRef nameRef = NULL;
    UInt32 dataSize = sizeof(CFStringRef);
    
    OSStatus status = AudioObjectGetPropertyData(
        deviceID,
        &propertyAddress,
        0,
        NULL,
        &dataSize,
        &nameRef
    );
    
    if (status != noErr || nameRef == NULL) return nil;
    
    return (__bridge_transfer NSString *)nameRef;
}

+ (NSString *)deviceUIDForID:(AudioObjectID)deviceID {
    AudioObjectPropertyAddress propertyAddress = {
        kAudioDevicePropertyDeviceUID,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    CFStringRef uidRef = NULL;
    UInt32 dataSize = sizeof(CFStringRef);
    
    OSStatus status = AudioObjectGetPropertyData(
        deviceID,
        &propertyAddress,
        0,
        NULL,
        &dataSize,
        &uidRef
    );
    
    if (status != noErr || uidRef == NULL) return nil;
    
    return (__bridge_transfer NSString *)uidRef;
}

+ (Float64)sampleRateForDeviceID:(AudioObjectID)deviceID {
    AudioObjectPropertyAddress propertyAddress = {
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    Float64 sampleRate = 0;
    UInt32 dataSize = sizeof(Float64);
    
    OSStatus status = AudioObjectGetPropertyData(
        deviceID,
        &propertyAddress,
        0,
        NULL,
        &dataSize,
        &sampleRate
    );
    
    return (status == noErr) ? sampleRate : 44100.0;
}

+ (UInt32)channelCountForDeviceID:(AudioObjectID)deviceID isInput:(BOOL)isInput {
    AudioObjectPropertyAddress propertyAddress = {
        kAudioDevicePropertyStreamConfiguration,
        isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 dataSize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(
        deviceID,
        &propertyAddress,
        0,
        NULL,
        &dataSize
    );
    
    if (status != noErr) return 0;
    
    AudioBufferList *bufferList = (AudioBufferList *)malloc(dataSize);
    
    status = AudioObjectGetPropertyData(
        deviceID,
        &propertyAddress,
        0,
        NULL,
        &dataSize,
        bufferList
    );
    
    if (status != noErr) {
        free(bufferList);
        return 0;
    }
    
    UInt32 channelCount = 0;
    for (UInt32 i = 0; i < bufferList->mNumberBuffers; i++) {
        channelCount += bufferList->mBuffers[i].mNumberChannels;
    }
    
    free(bufferList);
    return channelCount;
}

static void *deviceListChangeCallbackKey = &deviceListChangeCallbackKey;

+ (void)registerDeviceListChangeCallback:(void (^)(void))callback {
    // Store callback using associated object
    objc_setAssociatedObject(self, deviceListChangeCallbackKey, callback, OBJC_ASSOCIATION_COPY_NONATOMIC);
    
    // Register for hardware property changes
    AudioObjectPropertyAddress propertyAddress = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    AudioObjectAddPropertyListenerBlock(
        kAudioObjectSystemObject,
        &propertyAddress,
        dispatch_get_main_queue(),
        ^(UInt32 inNumberAddresses, const AudioObjectPropertyAddress *inAddresses) {
            void (^storedCallback)(void) = objc_getAssociatedObject(self, deviceListChangeCallbackKey);
            if (storedCallback) {
                storedCallback();
            }
            [[NSNotificationCenter defaultCenter] 
                postNotificationName:kManateeDeviceListChangedNotification 
                object:nil];
        }
    );
}

@end


// MARK: - BGMXPCClient Implementation

@interface BGMXPCClient ()
@property (nonatomic, strong) NSXPCConnection *connection;
@end

@implementation BGMXPCClient

static BGMXPCClient *sharedXPCClient = nil;

+ (instancetype)sharedClient {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedXPCClient = [[BGMXPCClient alloc] init];
    });
    return sharedXPCClient;
}

- (BOOL)isConnected {
    return self.connection != nil;
}

- (BOOL)startHelperIfNeeded {
    // TODO: Implement XPC connection to helper
    return YES;
}

- (void)stopHelper {
    [self.connection invalidate];
    self.connection = nil;
}

- (void)requestPrivilegedOperationWithType:(NSInteger)type
                                completion:(void (^)(BOOL, NSError *))completion {
    // TODO: Implement privileged operations
    if (completion) {
        completion(YES, nil);
    }
}

@end


// MARK: - C Functions

BOOL ManateeAudioSystemInitialize(void) {
    BGMDeviceWrapper *device = [BGMDeviceWrapper sharedDevice];
    return [device connect];
}

void ManateeAudioSystemShutdown(void) {
    BGMDeviceWrapper *device = [BGMDeviceWrapper sharedDevice];
    [device disconnect];
}

BOOL ManateeIsDriverInstalled(void) {
    BGMDeviceWrapper *device = [BGMDeviceWrapper sharedDevice];
    return [device connect];
}

NSString *ManateeGetDriverVersion(void) {
    // TODO: Get version from driver
    return @"1.0.0";
}

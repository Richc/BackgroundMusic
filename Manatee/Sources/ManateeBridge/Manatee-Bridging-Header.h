//
//  Manatee-Bridging-Header.h
//  Manatee
//
//  Bridging header for Objective-C and C++ interoperability
//  with BackgroundMusic driver components
//

#ifndef Manatee_Bridging_Header_h
#define Manatee_Bridging_Header_h

// Foundation & Core Audio
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>

// MARK: - Forward Declarations

// Note: BGM_Types.h will be included when integrating with the driver
// For standalone builds, we define minimal types here

// App volume data structure
typedef struct {
    CFStringRef mBundleID;
    pid_t mProcessID;
    Float32 mVolume;
    Float32 mPan;
    SInt32 mMuted;  // 0 = not muted, nonzero = muted
} BGMAppVolumeData;

// MARK: - Objective-C Wrapper Interface

/// Wrapper class for BGMDevice C++ functionality
/// Provides Swift-compatible interface for audio device operations
@interface BGMDeviceWrapper : NSObject

/// The AudioObjectID of the BGM device
@property (nonatomic, readonly) AudioObjectID deviceID;

/// Check if the BGM device is available
@property (nonatomic, readonly) BOOL isAvailable;

/// Get the current output device UID
@property (nonatomic, readonly, nullable) NSString *outputDeviceUID;

/// Shared instance
+ (nonnull instancetype)sharedDevice;

/// Initialize connection to BGM device
- (BOOL)connect;

/// Disconnect from BGM device
- (void)disconnect;

/// Set the output device by UID
- (BOOL)setOutputDeviceWithUID:(nonnull NSString *)uid;

/// Get volume for an application by bundle ID (0.0 - 1.0)
- (float)volumeForAppWithBundleID:(nonnull NSString *)bundleID;

/// Set volume for an application by bundle ID
- (BOOL)setVolume:(float)volume forAppWithBundleID:(nonnull NSString *)bundleID;

/// Get mute state for an application
- (BOOL)isMutedAppWithBundleID:(nonnull NSString *)bundleID;

/// Set mute state for an application
- (BOOL)setMuted:(BOOL)muted forAppWithBundleID:(nonnull NSString *)bundleID;

/// Get pan for an application (-1.0 to 1.0)
- (float)panForAppWithBundleID:(nonnull NSString *)bundleID;

/// Set pan for an application
- (BOOL)setPan:(float)pan forAppWithBundleID:(nonnull NSString *)bundleID;

/// Get all currently active audio clients (running apps producing audio)
- (nonnull NSArray<NSDictionary *> *)activeAudioClients;

/// Register for volume change notifications
- (void)registerVolumeChangeCallback:(void (^_Nonnull)(NSString * _Nonnull bundleID, float volume))callback;

/// Register for mute change notifications  
- (void)registerMuteChangeCallback:(void (^_Nonnull)(NSString * _Nonnull bundleID, BOOL muted))callback;

/// Register for client list change notifications
- (void)registerClientChangeCallback:(void (^_Nonnull)(void))callback;

@end


/// Wrapper for audio device utilities
@interface AudioDeviceUtilities : NSObject

/// Get all output audio devices
+ (nonnull NSArray<NSDictionary *> *)allOutputDevices;

/// Get all input audio devices
+ (nonnull NSArray<NSDictionary *> *)allInputDevices;

/// Get the default output device
+ (nullable NSDictionary *)defaultOutputDevice;

/// Get the default input device
+ (nullable NSDictionary *)defaultInputDevice;

/// Set the default output device by UID
+ (BOOL)setDefaultOutputDeviceWithUID:(nonnull NSString *)uid;

/// Get device name for AudioObjectID
+ (nullable NSString *)deviceNameForID:(AudioObjectID)deviceID;

/// Get device UID for AudioObjectID
+ (nullable NSString *)deviceUIDForID:(AudioObjectID)deviceID;

/// Get sample rate for device
+ (Float64)sampleRateForDeviceID:(AudioObjectID)deviceID;

/// Get channel count for device
+ (UInt32)channelCountForDeviceID:(AudioObjectID)deviceID isInput:(BOOL)isInput;

/// Register for device list change notifications
+ (void)registerDeviceListChangeCallback:(void (^_Nonnull)(void))callback;

@end


/// Wrapper for BGM XPC communication
@interface BGMXPCClient : NSObject

/// Shared instance
+ (nonnull instancetype)sharedClient;

/// Connection status
@property (nonatomic, readonly) BOOL isConnected;

/// Start the XPC helper if needed
- (BOOL)startHelperIfNeeded;

/// Stop the XPC helper
- (void)stopHelper;

/// Request privileged operation (e.g., install driver)
- (void)requestPrivilegedOperationWithType:(NSInteger)type
                                completion:(void (^_Nonnull)(BOOL success, NSError * _Nullable error))completion;

@end


// MARK: - C Function Declarations for Swift

/// Initialize the audio system
extern BOOL ManateeAudioSystemInitialize(void);

/// Shutdown the audio system
extern void ManateeAudioSystemShutdown(void);

/// Check if the virtual device driver is installed
extern BOOL ManateeIsDriverInstalled(void);

/// Get driver version string
extern NSString * _Nullable ManateeGetDriverVersion(void);


// MARK: - Constants

/// Notification names
extern NSString * _Nonnull const kManateeAudioClientsChangedNotification;
extern NSString * _Nonnull const kManateeDeviceListChangedNotification;
extern NSString * _Nonnull const kManateeVolumeChangedNotification;


#endif /* Manatee_Bridging_Header_h */

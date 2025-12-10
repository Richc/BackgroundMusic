// This file is part of Background Music.
//
// Background Music is free software: you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation, either version 2 of the
// License, or (at your option) any later version.
//
// Background Music is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Background Music. If not, see <http://www.gnu.org/licenses/>.

//
//  BGM_Clients.cpp
//  BGMDriver
//
//  Copyright © 2016, 2017, 2019 Kyle Neideck
//  Copyright © 2017 Andrew Tonner
//

// Self Include
#include "BGM_Clients.h"

// Local Includes
#include "BGM_Types.h"
#include "BGM_PlugIn.h"

// PublicUtility Includes
#include "CAException.h"
#include "CACFDictionary.h"
#include "CADispatchQueue.h"


#pragma mark Construction/Destruction

BGM_Clients::BGM_Clients(AudioObjectID inOwnerDeviceID, BGM_TaskQueue* inTaskQueue)
:
    mOwnerDeviceID(inOwnerDeviceID),
    mClientMap(inTaskQueue)
{
    mRelativeVolumeCurve.AddRange(kAppRelativeVolumeMinRawValue,
                                  kAppRelativeVolumeMaxRawValue,
                                  kAppRelativeVolumeMinDbValue,
                                  kAppRelativeVolumeMaxDbValue);
}

#pragma mark Add/Remove Clients

void    BGM_Clients::AddClient(BGM_Client inClient)
{
    CAMutex::Locker theLocker(mMutex);

    // Check whether this is the music player's client
    bool pidMatchesMusicPlayerProperty =
        (mMusicPlayerProcessIDProperty != 0 && inClient.mProcessID == mMusicPlayerProcessIDProperty);
    bool bundleIDMatchesMusicPlayerProperty =
        (mMusicPlayerBundleIDProperty != "" &&
         inClient.mBundleID.IsValid() &&
         inClient.mBundleID == mMusicPlayerBundleIDProperty);
    
    inClient.mIsMusicPlayer = (pidMatchesMusicPlayerProperty || bundleIDMatchesMusicPlayerProperty);
    
    if(inClient.mIsMusicPlayer)
    {
        DebugMsg("BGM_Clients::AddClient: Adding music player client. mClientID = %u", inClient.mClientID);
    }
    
    mClientMap.AddClient(inClient);
    
    // If we're adding BGMApp, update our local copy of its client ID
    if(inClient.mBundleID.IsValid() && inClient.mBundleID == kBGMAppBundleID)
    {
        mBGMAppClientID = inClient.mClientID;
    }
}

void    BGM_Clients::RemoveClient(const UInt32 inClientID)
{
    CAMutex::Locker theLocker(mMutex);
    
    BGM_Client theRemovedClient = mClientMap.RemoveClient(inClientID);
    
    // If we're removing BGMApp, clear our local copy of its client ID
    if(theRemovedClient.mClientID == mBGMAppClientID)
    {
        mBGMAppClientID = -1;
    }
}

#pragma mark IO Status

bool    BGM_Clients::StartIONonRT(UInt32 inClientID)
{
    CAMutex::Locker theLocker(mMutex);
    
    bool didStartIO = false;
    
    BGM_Client theClient;
    bool didFindClient = mClientMap.GetClientNonRT(inClientID, &theClient);
    
    ThrowIf(!didFindClient, BGM_InvalidClientException(), "BGM_Clients::StartIO: Cannot start IO for client that was never added");
    
    bool sendIsRunningNotification = false;
    bool sendIsRunningSomewhereOtherThanBGMAppNotification = false;

    if(!theClient.mDoingIO)
    {
        // Make sure we can start
        ThrowIf(mStartCount == UINT64_MAX, CAException(kAudioHardwareIllegalOperationError), "BGM_Clients::StartIO: failed to start because the ref count was maxxed out already");
        
        DebugMsg("BGM_Clients::StartIO: Client %u (%s, %d) starting IO",
                 inClientID,
                 CFStringGetCStringPtr(theClient.mBundleID.GetCFString(), kCFStringEncodingUTF8),
                 theClient.mProcessID);
        
        mClientMap.StartIONonRT(inClientID);
        
        mStartCount++;
        
        // Update mStartCountExcludingBGMApp
        if(!IsBGMApp(inClientID))
        {
            ThrowIf(mStartCountExcludingBGMApp == UINT64_MAX, CAException(kAudioHardwareIllegalOperationError), "BGM_Clients::StartIO: failed to start because mStartCountExcludingBGMApp was maxxed out already");
            
            mStartCountExcludingBGMApp++;
            
            if(mStartCountExcludingBGMApp == 1)
            {
                sendIsRunningSomewhereOtherThanBGMAppNotification = true;
            }
        }
        
        // Return true if no other clients were running IO before this one started, which means the device should start IO
        didStartIO = (mStartCount == 1);
        sendIsRunningNotification = didStartIO;
    }
    
    Assert(mStartCountExcludingBGMApp == mStartCount - 1 || mStartCountExcludingBGMApp == mStartCount,
           "mStartCount and mStartCountExcludingBGMApp are out of sync");
    
    SendIORunningNotifications(sendIsRunningNotification, sendIsRunningSomewhereOtherThanBGMAppNotification);

    return didStartIO;
}

bool    BGM_Clients::StopIONonRT(UInt32 inClientID)
{
    CAMutex::Locker theLocker(mMutex);
    
    bool didStopIO = false;
    
    BGM_Client theClient;
    bool didFindClient = mClientMap.GetClientNonRT(inClientID, &theClient);
    
    ThrowIf(!didFindClient, BGM_InvalidClientException(), "BGM_Clients::StopIO: Cannot stop IO for client that was never added");
    
    bool sendIsRunningNotification = false;
    bool sendIsRunningSomewhereOtherThanBGMAppNotification = false;
    
    if(theClient.mDoingIO)
    {
        DebugMsg("BGM_Clients::StopIO: Client %u (%s, %d) stopping IO",
                 inClientID,
                 CFStringGetCStringPtr(theClient.mBundleID.GetCFString(), kCFStringEncodingUTF8),
                 theClient.mProcessID);
        
        mClientMap.StopIONonRT(inClientID);
        
        ThrowIf(mStartCount <= 0, CAException(kAudioHardwareIllegalOperationError), "BGM_Clients::StopIO: Underflowed mStartCount");
        
        mStartCount--;
        
        // Update mStartCountExcludingBGMApp
        if(!IsBGMApp(inClientID))
        {
            ThrowIf(mStartCountExcludingBGMApp <= 0, CAException(kAudioHardwareIllegalOperationError), "BGM_Clients::StopIO: Underflowed mStartCountExcludingBGMApp");
            
            mStartCountExcludingBGMApp--;
            
            if(mStartCountExcludingBGMApp == 0)
            {
                sendIsRunningSomewhereOtherThanBGMAppNotification = true;
            }
        }
        
        // Return true if we stopped IO entirely (i.e. there are no clients still running IO)
        didStopIO = (mStartCount == 0);
        sendIsRunningNotification = didStopIO;
    }
    
    Assert(mStartCountExcludingBGMApp == mStartCount - 1 || mStartCountExcludingBGMApp == mStartCount,
           "mStartCount and mStartCountExcludingBGMApp are out of sync");
    
    SendIORunningNotifications(sendIsRunningNotification, sendIsRunningSomewhereOtherThanBGMAppNotification);
    
    return didStopIO;
}

bool    BGM_Clients::ClientsRunningIO() const
{
    return mStartCount > 0;
}

bool    BGM_Clients::ClientsOtherThanBGMAppRunningIO() const
{
    return mStartCountExcludingBGMApp > 0;
}

void    BGM_Clients::SendIORunningNotifications(bool sendIsRunningNotification, bool sendIsRunningSomewhereOtherThanBGMAppNotification) const
{
    if(sendIsRunningNotification || sendIsRunningSomewhereOtherThanBGMAppNotification)
    {
        CADispatchQueue::GetGlobalSerialQueue().Dispatch(false, ^{
            AudioObjectPropertyAddress theChangedProperties[2];
            UInt32 theNotificationCount = 0;

            if(sendIsRunningNotification)
            {
                DebugMsg("BGM_Clients::SendIORunningNotifications: Sending kAudioDevicePropertyDeviceIsRunning");
                theChangedProperties[0] = { kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster };
                theNotificationCount++;
            }

            if(sendIsRunningSomewhereOtherThanBGMAppNotification)
            {
                DebugMsg("BGM_Clients::SendIORunningNotifications: Sending kAudioDeviceCustomPropertyDeviceIsRunningSomewhereOtherThanBGMApp");
                theChangedProperties[theNotificationCount] = kBGMRunningSomewhereOtherThanBGMAppAddress;
                theNotificationCount++;
            }

            BGM_PlugIn::Host_PropertiesChanged(mOwnerDeviceID, theNotificationCount, theChangedProperties);
        });
    }
}

#pragma mark Music Player

bool    BGM_Clients::SetMusicPlayer(const pid_t inPID)
{
    ThrowIf(inPID < 0, BGM_InvalidClientPIDException(), "BGM_Clients::SetMusicPlayer: Invalid music player PID");
    
    CAMutex::Locker theLocker(mMutex);
    
    if(mMusicPlayerProcessIDProperty == inPID)
    {
        // We're not changing the properties, so return false
        return false;
    }
    
    mMusicPlayerProcessIDProperty = inPID;
    // Unset the bundle ID property
    mMusicPlayerBundleIDProperty = "";
    
    DebugMsg("BGM_Clients::SetMusicPlayer: Setting music player by PID. inPID=%d", inPID);
    
    // Update the clients' mIsMusicPlayer fields
    mClientMap.UpdateMusicPlayerFlags(inPID);
    
    return true;
}

bool    BGM_Clients::SetMusicPlayer(const CACFString inBundleID)
{
    Assert(inBundleID.IsValid(), "BGM_Clients::SetMusicPlayer: Invalid CACFString given as bundle ID");
    
    CAMutex::Locker theLocker(mMutex);
    
    if(mMusicPlayerBundleIDProperty == inBundleID)
    {
        // We're not changing the properties, so return false
        return false;
    }
    
    mMusicPlayerBundleIDProperty = inBundleID;
    // Unset the PID property
    mMusicPlayerProcessIDProperty = 0;
    
    DebugMsg("BGM_Clients::SetMusicPlayer: Setting music player by bundle ID. inBundleID=%s",
             CFStringGetCStringPtr(inBundleID.GetCFString(), kCFStringEncodingUTF8));
    
    // Update the clients' mIsMusicPlayer fields
    mClientMap.UpdateMusicPlayerFlags(inBundleID);
    
    return true;
}

bool    BGM_Clients::IsMusicPlayerRT(const UInt32 inClientID) const
{
    BGM_Client theClient;
    bool didGetClient = mClientMap.GetClientRT(inClientID, &theClient);
    return didGetClient && theClient.mIsMusicPlayer;
}

#pragma mark App Volumes

Float32 BGM_Clients::GetClientRelativeVolumeRT(UInt32 inClientID) const
{
    BGM_Client theClient;
    bool didGetClient = mClientMap.GetClientRT(inClientID, &theClient);
    return (didGetClient ? theClient.mRelativeVolume : 1.0f);
}

SInt32 BGM_Clients::GetClientPanPositionRT(UInt32 inClientID) const
{
    BGM_Client theClient;
    bool didGetClient = mClientMap.GetClientRT(inClientID, &theClient);
    return (didGetClient ? theClient.mPanPosition : kAppPanCenterRawValue);
}

BGM_Client* BGM_Clients::GetClientForEQRT(UInt32 inClientID) const
{
    return mClientMap.GetClientPtrRT(inClientID);
}

bool    BGM_Clients::SetClientsRelativeVolumes(const CACFArray inAppVolumes)
{
    bool didChangeAppVolumes = false;
    
    // Each element in appVolumes is a CFDictionary containing the process id and/or bundle id of an app, and its
    // new relative volume
    for(UInt32 i = 0; i < inAppVolumes.GetNumberItems(); i++)
    {
        CACFDictionary theAppVolume(false);
        inAppVolumes.GetCACFDictionary(i, theAppVolume);
        
        // Get the app's PID from the dict
        pid_t theAppPID;
        bool didFindPID = theAppVolume.GetSInt32(CFSTR(kBGMAppVolumesKey_ProcessID), theAppPID);
        
        // Get the app's bundle ID from the dict
        CACFString theAppBundleID;
        theAppBundleID.DontAllowRelease();
        theAppVolume.GetCACFString(CFSTR(kBGMAppVolumesKey_BundleID), theAppBundleID);
        
        ThrowIf(!didFindPID && !theAppBundleID.IsValid(),
                BGM_InvalidClientRelativeVolumeException(),
                "BGM_Clients::SetClientsRelativeVolumes: App volume was sent without PID or bundle ID for app");
        
        bool didGetVolume;
        {
            SInt32 theRawRelativeVolume;
            didGetVolume = theAppVolume.GetSInt32(CFSTR(kBGMAppVolumesKey_RelativeVolume), theRawRelativeVolume);
            
            if (didGetVolume) {
                ThrowIf(didGetVolume && (theRawRelativeVolume < kAppRelativeVolumeMinRawValue || theRawRelativeVolume > kAppRelativeVolumeMaxRawValue),
                        BGM_InvalidClientRelativeVolumeException(),
                        "BGM_Clients::SetClientsRelativeVolumes: Relative volume for app out of valid range");
                
                // Apply the volume curve to the raw volume
                //
                // mRelativeVolumeCurve uses the default kPow2Over1Curve transfer function, so we also multiply by 4 to
                // keep the middle volume equal to 1 (meaning apps' volumes are unchanged by default).
                Float32 theRelativeVolume = mRelativeVolumeCurve.ConvertRawToScalar(theRawRelativeVolume) * 4;

                // Try to update the client's volume, first by PID and then by bundle ID. Always try
                // both because apps can have multiple clients.
                if(mClientMap.SetClientsRelativeVolume(theAppPID, theRelativeVolume))
                {
                    didChangeAppVolumes = true;
                }

                if(mClientMap.SetClientsRelativeVolume(theAppBundleID, theRelativeVolume))
                {
                    didChangeAppVolumes = true;
                }

                // TODO: If the app isn't currently a client, we should add it to the past clients
                //       map, or update its past volume if it's already in there.
            }
        }
        
        bool didGetPanPosition;
        {
            SInt32 thePanPosition;
            didGetPanPosition = theAppVolume.GetSInt32(CFSTR(kBGMAppVolumesKey_PanPosition), thePanPosition);
            if (didGetPanPosition) {
                ThrowIf(didGetPanPosition && (thePanPosition < kAppPanLeftRawValue || thePanPosition > kAppPanRightRawValue),
                                              BGM_InvalidClientPanPositionException(),
                                              "BGM_Clients::SetClientsRelativeVolumes: Pan position for app out of valid range");
                
                if(mClientMap.SetClientsPanPosition(theAppPID, thePanPosition))
                {
                    didChangeAppVolumes = true;
                }

                if(mClientMap.SetClientsPanPosition(theAppBundleID, thePanPosition))
                {
                    didChangeAppVolumes = true;
                }

                // TODO: If the app isn't currently a client, we should add it to the past clients
                //       map, or update its past pan position if it's already in there.
            }
        }
        
        // Handle EQ settings (low, mid, high in dB from -12 to +12)
        bool didGetEQ = false;
        {
            SInt32 theEQLow, theEQMid, theEQHigh;
            bool hasLow = theAppVolume.GetSInt32(CFSTR(kBGMAppVolumesKey_EQLowGain), theEQLow);
            bool hasMid = theAppVolume.GetSInt32(CFSTR(kBGMAppVolumesKey_EQMidGain), theEQMid);
            bool hasHigh = theAppVolume.GetSInt32(CFSTR(kBGMAppVolumesKey_EQHighGain), theEQHigh);
            
            if (hasLow || hasMid || hasHigh) {
                // Validate ranges (EQ is stored as SInt32 in 10ths of dB, -120 to 120)
                if (hasLow) {
                    ThrowIf(theEQLow < kAppEQGainMinRawValue || theEQLow > kAppEQGainMaxRawValue,
                            BGM_InvalidClientRelativeVolumeException(),
                            "BGM_Clients::SetClientsRelativeVolumes: EQ low gain out of valid range");
                }
                if (hasMid) {
                    ThrowIf(theEQMid < kAppEQGainMinRawValue || theEQMid > kAppEQGainMaxRawValue,
                            BGM_InvalidClientRelativeVolumeException(),
                            "BGM_Clients::SetClientsRelativeVolumes: EQ mid gain out of valid range");
                }
                if (hasHigh) {
                    ThrowIf(theEQHigh < kAppEQGainMinRawValue || theEQHigh > kAppEQGainMaxRawValue,
                            BGM_InvalidClientRelativeVolumeException(),
                            "BGM_Clients::SetClientsRelativeVolumes: EQ high gain out of valid range");
                }
                
                // Convert from 10ths of dB to dB, use kAppEQGainNoValue for missing values
                Float32 lowDB = hasLow ? static_cast<Float32>(theEQLow) / 10.0f : static_cast<Float32>(kAppEQGainNoValue);
                Float32 midDB = hasMid ? static_cast<Float32>(theEQMid) / 10.0f : static_cast<Float32>(kAppEQGainNoValue);
                Float32 highDB = hasHigh ? static_cast<Float32>(theEQHigh) / 10.0f : static_cast<Float32>(kAppEQGainNoValue);
                
                // Get sample rate from the device (default to 48kHz)
                Float64 sampleRate = 48000.0;
                
                if(mClientMap.SetClientsEQ(theAppPID, lowDB, midDB, highDB, sampleRate))
                {
                    didChangeAppVolumes = true;
                    didGetEQ = true;
                }
                
                if(mClientMap.SetClientsEQ(theAppBundleID, lowDB, midDB, highDB, sampleRate))
                {
                    didChangeAppVolumes = true;
                    didGetEQ = true;
                }
            }
        }
        
        ThrowIf(!didGetVolume && !didGetPanPosition && !didGetEQ,
                BGM_InvalidClientRelativeVolumeException(),
                "BGM_Clients::SetClientsRelativeVolumes: No volume, pan position, or EQ in request");
    }
    
    return didChangeAppVolumes;
}

#pragma mark App Routing

bool    BGM_Clients::SetRoute(pid_t inSourcePID, pid_t inDestPID, Float32 inGain, bool inEnabled)
{
    CAMutex::Locker theLocker(mMutex);
    
    // Look for existing route
    for(auto& route : mRoutes)
    {
        if(route.mSourcePID == inSourcePID && route.mDestPID == inDestPID)
        {
            // Update existing route
            bool changed = (route.mGain != inGain || route.mEnabled != inEnabled);
            route.mGain = inGain;
            route.mEnabled = inEnabled;
            
            // If disabling, we could clean up routing buffers, but keep them for quick re-enable
            
            return changed;
        }
    }
    
    // Add new route
    if(inEnabled)
    {
        BGM_AudioRoute newRoute;
        newRoute.mSourcePID = inSourcePID;
        newRoute.mDestPID = inDestPID;
        newRoute.mGain = inGain;
        newRoute.mEnabled = inEnabled;
        mRoutes.push_back(newRoute);
        
        // Allocate routing buffer for source client
        mClientMap.AllocateRoutingBufferForPID(inSourcePID);
        
        DebugMsg("BGM_Clients::SetRoute: Added route from PID %d to PID %d, gain=%.2f",
                 inSourcePID, inDestPID, inGain);
        
        return true;
    }
    
    return false;
}

CFArrayRef  BGM_Clients::CopyRoutesAsArray() const
{
    CAMutex::Locker theLocker(mMutex);
    
    CFMutableArrayRef routesArray = CFArrayCreateMutable(kCFAllocatorDefault, 
                                                          static_cast<CFIndex>(mRoutes.size()),
                                                          &kCFTypeArrayCallBacks);
    if(!routesArray)
    {
        return nullptr;
    }
    
    for(const auto& route : mRoutes)
    {
        CFMutableDictionaryRef routeDict = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                                      4,
                                                                      &kCFTypeDictionaryKeyCallBacks,
                                                                      &kCFTypeDictionaryValueCallBacks);
        if(!routeDict)
        {
            continue;
        }
        
        // Add source PID
        CFNumberRef sourcePID = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &route.mSourcePID);
        if(sourcePID)
        {
            CFDictionarySetValue(routeDict, CFSTR(kBGMAppRoutingKey_SourceProcessID), sourcePID);
            CFRelease(sourcePID);
        }
        
        // Add dest PID
        CFNumberRef destPID = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &route.mDestPID);
        if(destPID)
        {
            CFDictionarySetValue(routeDict, CFSTR(kBGMAppRoutingKey_DestProcessID), destPID);
            CFRelease(destPID);
        }
        
        // Add gain
        CFNumberRef gain = CFNumberCreate(kCFAllocatorDefault, kCFNumberFloat32Type, &route.mGain);
        if(gain)
        {
            CFDictionarySetValue(routeDict, CFSTR(kBGMAppRoutingKey_Gain), gain);
            CFRelease(gain);
        }
        
        // Add enabled
        CFDictionarySetValue(routeDict, CFSTR(kBGMAppRoutingKey_Enabled), 
                            route.mEnabled ? kCFBooleanTrue : kCFBooleanFalse);
        
        CFArrayAppendValue(routesArray, routeDict);
        CFRelease(routeDict);
    }
    
    return routesArray;
}

bool    BGM_Clients::SetRoutesFromArray(const CACFArray inRoutes)
{
    CAMutex::Locker theLocker(mMutex);
    
    bool didChange = false;
    
    for(UInt32 i = 0; i < inRoutes.GetNumberItems(); i++)
    {
        CACFDictionary theRoute(false);
        inRoutes.GetCACFDictionary(i, theRoute);
        
        if(!theRoute.IsValid())
        {
            continue;
        }
        
        // Get source PID
        pid_t sourcePID;
        if(!theRoute.GetSInt32(CFSTR(kBGMAppRoutingKey_SourceProcessID), sourcePID))
        {
            continue;
        }
        
        // Get dest PID
        pid_t destPID;
        if(!theRoute.GetSInt32(CFSTR(kBGMAppRoutingKey_DestProcessID), destPID))
        {
            continue;
        }
        
        // Get gain (default to 1.0)
        Float32 gain = 1.0f;
        theRoute.GetFloat32(CFSTR(kBGMAppRoutingKey_Gain), gain);
        
        // Get enabled (default to true)
        bool enabled = true;
        theRoute.GetBool(CFSTR(kBGMAppRoutingKey_Enabled), enabled);
        
        // Use the public SetRoute which will handle locking - but we already hold the lock
        // So directly manipulate mRoutes here
        bool found = false;
        for(auto& existingRoute : mRoutes)
        {
            if(existingRoute.mSourcePID == sourcePID && existingRoute.mDestPID == destPID)
            {
                if(existingRoute.mGain != gain || existingRoute.mEnabled != enabled)
                {
                    existingRoute.mGain = gain;
                    existingRoute.mEnabled = enabled;
                    didChange = true;
                }
                found = true;
                break;
            }
        }
        
        if(!found && enabled)
        {
            BGM_AudioRoute newRoute;
            newRoute.mSourcePID = sourcePID;
            newRoute.mDestPID = destPID;
            newRoute.mGain = gain;
            newRoute.mEnabled = enabled;
            mRoutes.push_back(newRoute);
            
            // Allocate routing buffer for source client
            mClientMap.AllocateRoutingBufferForPID(sourcePID);
            
            didChange = true;
        }
    }
    
    return didChange;
}

void    BGM_Clients::ClearRoutesForClient(pid_t inProcessID)
{
    CAMutex::Locker theLocker(mMutex);
    
    // Remove all routes where this process is source or destination
    auto it = mRoutes.begin();
    while(it != mRoutes.end())
    {
        if(it->mSourcePID == inProcessID || it->mDestPID == inProcessID)
        {
            DebugMsg("BGM_Clients::ClearRoutesForClient: Removing route from PID %d to PID %d",
                     it->mSourcePID, it->mDestPID);
            it = mRoutes.erase(it);
        }
        else
        {
            ++it;
        }
    }
    
    // Deallocate routing buffer for this client
    mClientMap.DeallocateRoutingBufferForPID(inProcessID);
}

void    BGM_Clients::StoreClientAudioRT(UInt32 inClientID, const Float32* inBuffer, UInt32 inNumFrames)
{
    // Check if this client is a routing source
    BGM_Client* theClient = mClientMap.GetClientPtrRT(inClientID);
    if(!theClient)
    {
        return;
    }
    
    // Check if any routes use this client as source
    bool isRoutingSource = false;
    for(const auto& route : mRoutes)
    {
        if(route.mEnabled && route.mSourcePID == theClient->mProcessID)
        {
            isRoutingSource = true;
            break;
        }
    }
    
    if(isRoutingSource)
    {
        // Debug: log that we're storing audio
        static int storeCount = 0;
        if(storeCount++ % 1000 == 0)
        {
            DebugMsg("BGM_Clients::StoreClientAudioRT: Storing %u frames from client %u (PID %d)",
                     inNumFrames, inClientID, theClient->mProcessID);
        }
        theClient->StoreToRoutingBuffer(inBuffer, inNumFrames, 0.0);
    }
}

void    BGM_Clients::MixRoutedAudioRT(UInt32 inClientID, Float32* ioBuffer, UInt32 inNumFrames)
{
    // Get the destination client to find its process ID
    BGM_Client* destClient = mClientMap.GetClientPtrRT(inClientID);
    if(!destClient)
    {
        return;
    }
    
    pid_t destPID = destClient->mProcessID;
    
    // Debug: count how many routes we find
    int routeCount = 0;
    
    // Find all routes that target this client
    for(const auto& route : mRoutes)
    {
        if(!route.mEnabled || route.mDestPID != destPID)
        {
            continue;
        }
        
        routeCount++;
        
        // Find the source client
        BGM_Client* sourceClient = mClientMap.GetClientByPIDRT(route.mSourcePID);
        if(!sourceClient)
        {
            DebugMsg("BGM_Clients::MixRoutedAudioRT: Source client PID %d not found!", route.mSourcePID);
            continue;
        }
        
        // Fetch audio from source's routing buffer and mix into destination
        // The buffer stores frames sequentially. After writing N frames, writePos points
        // to the next position to write. To read the most recent N frames:
        // - Frame 0 (oldest of the N) is at writePos - N
        // - Frame N-1 (newest) is at writePos - 1
        // We add a small safety margin to avoid reading data that's still being written
        Float32 gain = route.mGain;
        
        // Read the last inNumFrames that were written, with a small safety margin
        // Offset of 1 means "the most recently written frame"
        // Offset of inNumFrames means "the oldest of the last inNumFrames frames"
        for(UInt32 frame = 0; frame < inNumFrames; frame++)
        {
            // For frame 0 (first output frame), read the oldest available data
            // For frame inNumFrames-1 (last output frame), read the newest data
            // sampleOffset = inNumFrames - frame means:
            //   frame 0 -> offset inNumFrames (oldest)
            //   frame inNumFrames-1 -> offset 1 (newest)
            UInt64 sampleOffset = inNumFrames - frame;
            
            // Fetch left and right channels
            Float32 leftSample = sourceClient->FetchFromRoutingBuffer(0, sampleOffset);
            Float32 rightSample = sourceClient->FetchFromRoutingBuffer(1, sampleOffset);
            
            // Mix with gain
            ioBuffer[frame * 2] += leftSample * gain;
            ioBuffer[frame * 2 + 1] += rightSample * gain;
        }
        
        // Debug logging
        static int mixCount = 0;
        if(mixCount++ % 1000 == 0)
        {
            DebugMsg("BGM_Clients::MixRoutedAudioRT: Mixed %u frames from PID %d to client %u (PID %d)",
                     inNumFrames, route.mSourcePID, inClientID, destPID);
        }
    }
    
    // Debug: if we expected routes but found none
    static int noRouteCount = 0;
    if(routeCount == 0 && noRouteCount++ % 1000 == 0)
    {
        DebugMsg("BGM_Clients::MixRoutedAudioRT: No routes found for client %u (PID %d), total routes: %zu",
                 inClientID, destPID, mRoutes.size());
    }
}

bool    BGM_Clients::HasIncomingRoutesRT(UInt32 inClientID) const
{
    // Get the client to find its process ID
    BGM_Client* theClient = mClientMap.GetClientPtrRT(inClientID);
    if(!theClient)
    {
        DebugMsg("BGM_Clients::HasIncomingRoutesRT: No client found for clientID %u", inClientID);
        return false;
    }
    
    pid_t clientPID = theClient->mProcessID;
    
    // Check if any enabled routes target this client
    for(const auto& route : mRoutes)
    {
        if(route.mEnabled && route.mDestPID == clientPID)
        {
            DebugMsg("BGM_Clients::HasIncomingRoutesRT: Client %u (PID %d) HAS incoming route from PID %d",
                     inClientID, clientPID, route.mSourcePID);
            return true;
        }
    }
    
    return false;
}


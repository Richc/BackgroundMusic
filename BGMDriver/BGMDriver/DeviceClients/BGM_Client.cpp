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
//  BGM_Client.cpp
//  BGMDriver
//
//  Copyright © 2016 Kyle Neideck
//

// Self Include
#include "BGM_Client.h"


BGM_Client::BGM_Client(const AudioServerPlugInClientInfo* inClientInfo)
:
    mClientID(inClientInfo->mClientID),
    mProcessID(inClientInfo->mProcessID),
    mIsNativeEndian(inClientInfo->mIsNativeEndian),
    mBundleID(inClientInfo->mBundleID)
{
    // The bundle ID ref we were passed is only valid until our plugin returns control to the HAL, so we need to retain
    // it. (CACFString will handle the rest of its ownership/destruction.)
    if(inClientInfo->mBundleID != NULL)
    {
        CFRetain(inClientInfo->mBundleID);
    }
}

void    BGM_Client::Copy(const BGM_Client& inClient)
{
    mClientID = inClient.mClientID;
    mProcessID = inClient.mProcessID;
    mBundleID = inClient.mBundleID;
    mIsNativeEndian = inClient.mIsNativeEndian;
    mDoingIO = inClient.mDoingIO;
    mIsMusicPlayer = inClient.mIsMusicPlayer;
    mRelativeVolume = inClient.mRelativeVolume;
    mPanPosition = inClient.mPanPosition;
    
    // Copy EQ settings
    mEQLowGain = inClient.mEQLowGain;
    mEQMidGain = inClient.mEQMidGain;
    mEQHighGain = inClient.mEQHighGain;
    
    // Copy outgoing routes
    mOutgoingRoutes = inClient.mOutgoingRoutes;
    
    // Note: routing buffer is NOT copied - it stays with original client
    // Each client instance needs its own buffer
}

void    BGM_Client::AllocateRoutingBuffer()
{
    if (!mRoutingBufferAllocated && mRoutingBuffer == nullptr)
    {
        mRoutingBuffer = new Float32[kRoutingBufferFrames * kRoutingBufferChannels];
        // Zero the buffer
        memset(mRoutingBuffer, 0, kRoutingBufferFrames * kRoutingBufferChannels * sizeof(Float32));
        mRoutingBufferAllocated = true;
        mRoutingBufferWritePos = 0;
    }
}

void    BGM_Client::DeallocateRoutingBuffer()
{
    if (mRoutingBufferAllocated && mRoutingBuffer != nullptr)
    {
        delete[] mRoutingBuffer;
        mRoutingBuffer = nullptr;
        mRoutingBufferAllocated = false;
        mRoutingBufferWritePos = 0;
    }
}

void    BGM_Client::StoreToRoutingBuffer(const Float32* inBuffer, UInt32 inFrameCount, Float64 inSampleTime)
{
    if (!mRoutingBufferAllocated || mRoutingBuffer == nullptr)
    {
        return;
    }
    
    // Store interleaved stereo samples in circular buffer
    UInt64 writePos = mRoutingBufferWritePos.load(std::memory_order_relaxed);
    
    for (UInt32 frame = 0; frame < inFrameCount; frame++)
    {
        UInt32 bufferOffset = (writePos % kRoutingBufferFrames) * kRoutingBufferChannels;
        mRoutingBuffer[bufferOffset + 0] = inBuffer[frame * 2 + 0];  // Left
        mRoutingBuffer[bufferOffset + 1] = inBuffer[frame * 2 + 1];  // Right
        writePos++;
    }
    
    mRoutingBufferWritePos.store(writePos, std::memory_order_release);
    mRoutingBufferSampleTime = inSampleTime + inFrameCount;
}

Float32 BGM_Client::FetchFromRoutingBuffer(SInt32 inChannel, UInt64 inSampleOffset) const
{
    if (!mRoutingBufferAllocated || mRoutingBuffer == nullptr)
    {
        return 0.0f;
    }
    
    // Calculate buffer position
    UInt64 readPos = mRoutingBufferWritePos.load(std::memory_order_acquire);
    
    // We want to read data that was written inSampleOffset frames ago
    // Make sure we don't underflow
    if (readPos < inSampleOffset)
    {
        return 0.0f;
    }
    
    UInt64 targetPos = readPos - inSampleOffset;
    UInt32 bufferOffset = (targetPos % kRoutingBufferFrames) * kRoutingBufferChannels;
    
    // Bounds check the channel
    if (inChannel < 0 || inChannel >= static_cast<SInt32>(kRoutingBufferChannels))
    {
        return 0.0f;
    }
    
    return mRoutingBuffer[bufferOffset + static_cast<UInt32>(inChannel)];
}


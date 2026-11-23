#import <MTCallFrameBridge/MTCallFrameBridge.h>

#import <os/lock.h>

static os_unfair_lock mtCallFrameLock = OS_UNFAIR_LOCK_INIT;
static MTCallFrameProcessorBlock mtCallFrameProcessor = nil;

@implementation MTCallFrameBridge

+ (void)setProcessor:(MTCallFrameProcessorBlock _Nullable)processor {
    MTCallFrameProcessorBlock copied = [processor copy];
    os_unfair_lock_lock(&mtCallFrameLock);
    mtCallFrameProcessor = copied;
    os_unfair_lock_unlock(&mtCallFrameLock);
}

+ (BOOL)hasProcessor {
    os_unfair_lock_lock(&mtCallFrameLock);
    BOOL result = mtCallFrameProcessor != nil;
    os_unfair_lock_unlock(&mtCallFrameLock);
    return result;
}

+ (CVPixelBufferRef _Nullable)copyProcessedPixelBuffer:(CVPixelBufferRef)pixelBuffer isFrontCamera:(BOOL)isFrontCamera rotation:(int)rotation {
    os_unfair_lock_lock(&mtCallFrameLock);
    MTCallFrameProcessorBlock processor = mtCallFrameProcessor;
    os_unfair_lock_unlock(&mtCallFrameLock);
    if (processor == nil) {
        return NULL;
    }
    CVPixelBufferRef result = processor(pixelBuffer, isFrontCamera, rotation);
    if (result == NULL) {
        return NULL;
    }
    if (CVPixelBufferGetWidth(result) != CVPixelBufferGetWidth(pixelBuffer) || CVPixelBufferGetHeight(result) != CVPixelBufferGetHeight(pixelBuffer) || CVPixelBufferGetPixelFormatType(result) != CVPixelBufferGetPixelFormatType(pixelBuffer)) {
        CVPixelBufferRelease(result);
        return NULL;
    }
    return result;
}

@end

//
//  GPScreenVideoRecording.m
//  ScreenVideoRecording
//
//  Created by German Pereyra on 10/6/14.
//
//

#import "GPScreenVideoRecording.h"
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import "KTouchPointerWindow.h"

#define kMaxScreenshotCount 150
#define kVideosTemporalFolder @"videos/tmp"

@interface GPScreenVideoRecording ()
@property (strong, nonatomic) CADisplayLink *displayLink;
@property (nonatomic) CGSize winSize;
@property (nonatomic) CGFloat scale;
@property (nonatomic) NSInteger screenShotloop;
@property (nonatomic) NSInteger videoloop;
@property (nonatomic) CFTimeInterval firstTimeStamp;
@end

@implementation GPScreenVideoRecording {
    dispatch_queue_t _screenTaker_queue;
    dispatch_queue_t _FSWriter_queue;
    dispatch_queue_t _videoWriter_queue;
    dispatch_semaphore_t _pixelAppendSemaphore;
    dispatch_semaphore_t _writeVideoSemaphore;
    
    int numberOfScreenshots;
    AVAssetWriter *videoWriter;
}

- (NSString *)filesPath:(BOOL)video {
    NSString *_filesPath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/videos/video%@_%li", self.videoName, (video ? (long)self.videoloop : (long)self.screenShotloop)]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:_filesPath])
        [[NSFileManager defaultManager] createDirectoryAtPath:_filesPath withIntermediateDirectories:YES attributes:nil error:nil];
    
    return _filesPath;
}

- (NSString *)videosTemporalFolder {
    return [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"/Documents/%@/",kVideosTemporalFolder]];
}


#pragma mark - Initialization methods
- (instancetype)init {
    self = [super init];
    if (self) {
        self.videoName = @"asdasd";
        [self setupWriter];
    }
    return self;
}

- (instancetype)initWithTitle:(NSString *)title {
    self = [super init];
    if (self) {
        self.videoName = title;
        [self setupWriter];
    }
    return self;
}

- (void)setupWriter {
    UIWindow *mainWindow = [[[UIApplication sharedApplication] windows] objectAtIndex:0];
    _winSize = mainWindow.bounds.size;
    _scale = [UIScreen mainScreen].scale;
    // record half size resolution for retina iPads
    if ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) && _scale > 1) {
        _scale = 1.0;
    }
    _screenTaker_queue = dispatch_queue_create("GPScreenVideoRecording.screenTaker_queue", DISPATCH_QUEUE_SERIAL);
    _FSWriter_queue = dispatch_queue_create("GPScreenVideoRecording.FSWriter_queue", DISPATCH_QUEUE_SERIAL);
    _videoWriter_queue = dispatch_queue_create("GPScreenVideoRecording._videoWriter_queue", DISPATCH_QUEUE_SERIAL);
    _pixelAppendSemaphore = dispatch_semaphore_create(1);
    _writeVideoSemaphore = dispatch_semaphore_create(1);
}

#pragma mark - Public methods
- (void)startCapturing {
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(takeScreenShot)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    KTouchPointerWindowInstall();
}

- (void)stopCapturing {
    [_displayLink invalidate];
}

#pragma mark - Screen methods
- (void)takeScreenShot {
    if (dispatch_semaphore_wait(_pixelAppendSemaphore, DISPATCH_TIME_NOW) != 0) {
        return;
    }
    dispatch_async(_screenTaker_queue, ^{
        if (numberOfScreenshots >= kMaxScreenshotCount) {
            if (!dispatch_semaphore_wait(_writeVideoSemaphore, DISPATCH_TIME_NOW) != 0) {
                self.screenShotloop++;
                numberOfScreenshots = 0;
                self.firstTimeStamp = 0;
                [self videoFromImages];
            }
        }
        UIWindow *mainWindow = [[[UIApplication sharedApplication] windows] objectAtIndex:0];
        
        UIGraphicsBeginImageContext(_winSize);
        [mainWindow.layer renderInContext:UIGraphicsGetCurrentContext()];
        __block UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        dispatch_async(_FSWriter_queue, ^{
            NSData * data = UIImagePNGRepresentation(image);
            NSString *filePathForScreenshot = [NSString stringWithFormat:@"%@/screen_%f.png", [self filesPath:NO], _displayLink.timestamp];
            [data writeToFile:filePathForScreenshot atomically:YES];
            numberOfScreenshots++;
            dispatch_semaphore_signal(_pixelAppendSemaphore);
        });
    });
}

#pragma mark - Video methods
- (void)videoFromImages
{
    dispatch_async(_videoWriter_queue, ^{
        NSError *error;
        
        videoWriter = [[AVAssetWriter alloc] initWithURL:
                       [NSURL fileURLWithPath:[[self videosTemporalFolder] stringByAppendingPathComponent:[NSString stringWithFormat:@"/output%ld.mp4", (long)self.videoloop]]] fileType:AVFileTypeQuickTimeMovie
                                                   error:&error];
        if (!error) {
            NSParameterAssert(videoWriter);
            
            NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                           AVVideoCodecH264, AVVideoCodecKey,
                                           [NSNumber numberWithInt:_winSize.width], AVVideoWidthKey,
                                           [NSNumber numberWithInt:_winSize.height], AVVideoHeightKey,
                                           nil];
            
            AVAssetWriterInput* videoWriterInput = [AVAssetWriterInput
                                                    assetWriterInputWithMediaType:AVMediaTypeVideo
                                                    outputSettings:videoSettings];
            
            
            AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
                                                             assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoWriterInput
                                                             sourcePixelBufferAttributes:nil];
            
            NSParameterAssert(videoWriterInput);
            NSParameterAssert([videoWriter canAddInput:videoWriterInput]);
            
            [videoWriter addInput:videoWriterInput];
            [videoWriter startWriting];
            [videoWriter startSessionAtSourceTime:kCMTimeZero];
            
            NSArray *images = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self filesPath:YES] error:&error];
            
            int i = 0;
            while (i < images.count) {
                
                NSString *imgPath = [images objectAtIndex:i];
                
                if (![[imgPath pathExtension] isEqualToString:@"png"]) {
                    i++;
                    continue;
                }
                UIImage *img = [UIImage imageWithContentsOfFile:[[self filesPath:YES] stringByAppendingFormat:@"/%@",imgPath]];
                
                NSString *firstPart = [imgPath componentsSeparatedByString:@"_"][1];
                
                float timed = [[firstPart stringByReplacingOccurrencesOfString:@".png" withString:@""] floatValue];
                
                if (!self.firstTimeStamp) {
                    self.firstTimeStamp = timed;
                }
                if (adaptor.assetWriterInput.readyForMoreMediaData){
                    CFTimeInterval elapsed = (timed - self.firstTimeStamp);
                    CMTime time = CMTimeMakeWithSeconds(elapsed, 1000);
                    CVPixelBufferRef pixelBuffer = [self pixelBufferFromCGImage:[img CGImage]];
                    BOOL success = [adaptor appendPixelBuffer:pixelBuffer withPresentationTime:time];
                    if (!success) {
                        NSLog(@"Warning: Unable to write buffer to video");
                    }
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
                    CVPixelBufferRelease(pixelBuffer);
                    i++;
                }else{
                    [NSThread sleepForTimeInterval:.1];
                }
            }
            
            [videoWriterInput markAsFinished];
            
            [videoWriter finishWritingWithCompletionHandler:^{
                NSError *error;
                [[NSFileManager defaultManager] removeItemAtPath:[self filesPath:YES] error:&error];
                if (error)
                    NSLog(@"error removing path: %@", error);
                
                self.videoloop++;
                NSLog(@"finished"); // Never gets called
                dispatch_semaphore_signal(_writeVideoSemaphore);
            }];
        }
        else {
            NSLog(@"%@", error.localizedDescription);
        }
    });
}

- (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image
{
    
    NSDictionary *options =
    [NSDictionary dictionaryWithObjectsAndKeys:
     [NSNumber numberWithBool:YES],
     kCVPixelBufferCGImageCompatibilityKey,
     [NSNumber numberWithBool:YES],
     kCVPixelBufferCGBitmapContextCompatibilityKey,
     nil];
    CVPixelBufferRef pxbuffer = NULL;
    
    CVReturn status =
    CVPixelBufferCreate(
                        kCFAllocatorDefault, _winSize.width, _winSize.height,
                        kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef)options,
                        &pxbuffer);
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
                                                 pxdata, _winSize.width, _winSize.height,
                                                 8, CVPixelBufferGetBytesPerRow(pxbuffer),
                                                 rgbColorSpace,
                                                 (CGBitmapInfo)kCGBitmapByteOrder32Little |
                                                 kCGImageAlphaPremultipliedFirst);
    
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image),
                                           CGImageGetHeight(image)), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    
    return pxbuffer;
}

- (NSString*) applicationDocumentsDirectory

{
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}

- (void)mergeVideos
{
    AVMutableComposition* composition = [[AVMutableComposition alloc] init];
    AVMutableCompositionTrack * composedTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                         preferredTrackID:kCMPersistentTrackID_Invalid];
    NSMutableArray *assets = [NSMutableArray arrayWithArray:@[]];
    NSError *error;

    NSArray *allVideosPath = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self videosTemporalFolder] error:&error];
    if (error)
        NSLog(@"there was an error while getting the videos path: %@", error);
    
    for (NSString *videoPath in allVideosPath) {
        if (![[videoPath pathExtension] isEqualToString:@"mp4"]) {
            continue;
        }
        
        NSString *path = [[self videosTemporalFolder] stringByAppendingFormat:@"/%@",videoPath];
        AVURLAsset *video = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
        [assets addObject:video];
    }
    
    int i = assets.count;
    while (i > 0 ) {
        AVURLAsset *videoAsset = [assets objectAtIndex:i - 1];
        if ([[videoAsset tracksWithMediaType:AVMediaTypeVideo] count] == 0) {
            i--;
            continue;
        }
        [composedTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoAsset.duration)
                           ofTrack:[[videoAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0]
                            atTime:kCMTimeZero
                             error:nil];
        i--;
    }
    
    NSString* documentsDirectory = [self applicationDocumentsDirectory];
    NSString* myDocumentPath= [documentsDirectory stringByAppendingPathComponent:@"merge_video.mp4"];
    NSURL *url = [[NSURL alloc] initFileURLWithPath: myDocumentPath];
    if([[NSFileManager defaultManager] fileExistsAtPath:myDocumentPath])
    {
        [[NSFileManager defaultManager] removeItemAtPath:myDocumentPath error:nil];
    }
    
    AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetHighestQuality];
    exporter.outputURL=url;
    exporter.outputFileType = @"com.apple.quicktime-movie";
    exporter.shouldOptimizeForNetworkUse = YES;
    [exporter exportAsynchronouslyWithCompletionHandler:^{
        switch ([exporter status]) {
            case AVAssetExportSessionStatusUnknown:
                NSLog(@"StatusUnknown");
                break;
            case AVAssetExportSessionStatusWaiting:
                NSLog(@"Waiting");
                break;
            case AVAssetExportSessionStatusExporting:
                NSLog(@"Exporting");
                break;
            case AVAssetExportSessionStatusCompleted:
                NSLog(@"Completed");
                break;
            case AVAssetExportSessionStatusFailed:
                NSLog(@"Failed");
                break;
            case AVAssetExportSessionStatusCancelled:
                NSLog(@"Cancelled");
                break;
            default:
                NSLog(@"unknown");
                break;
        }
        
    }];
}



@end

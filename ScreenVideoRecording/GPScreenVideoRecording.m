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
#define kFramesMod 1
#define kVideoScale 0.7
#define kVideosTemporalFolder @"videos/tmp"
#define kScreenshotsTemporalFolder @"videos/screenshot"

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
    NSString *_filesPath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/%@/screenshot_%li", kScreenshotsTemporalFolder, (video ? (long)self.videoloop : (long)self.screenShotloop)]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:_filesPath])
        [[NSFileManager defaultManager] createDirectoryAtPath:_filesPath withIntermediateDirectories:YES attributes:nil error:nil];
    
    return _filesPath;
}

- (NSString *)videosTemporalFolder {
    NSString *_filesPath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"/Documents/%@/",kVideosTemporalFolder]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:_filesPath])
        [[NSFileManager defaultManager] createDirectoryAtPath:_filesPath withIntermediateDirectories:YES attributes:nil error:nil];
    return _filesPath;
}


#pragma mark - Initialization methods
- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupWriter];
    }
    return self;
}

- (instancetype)initWithTitle:(NSString *)title {
    self = [super init];
    if (self) {
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
    if (!_pixelAppendSemaphore) {
        [self setupWriter];
    }
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(takeScreenShot)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    KTouchPointerWindowInstall();
}

- (void)stopCapturing {
    [_displayLink invalidate];
    [self finishWithPendingScreenshots];
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
                [self videoFromImages:nil];
            }
        }
        UIWindow *mainWindow = [[[UIApplication sharedApplication] windows] objectAtIndex:0];
        
        UIGraphicsBeginImageContext(_winSize);
        [mainWindow.layer renderInContext:UIGraphicsGetCurrentContext()];
        __block UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        dispatch_async(_FSWriter_queue, ^{
            if (numberOfScreenshots % kFramesMod == 0) {
                NSData * data = UIImagePNGRepresentation(image);
                NSString *filePathForScreenshot = [NSString stringWithFormat:@"%@/screen_%f.png", [self filesPath:NO], _displayLink.timestamp];
                [data writeToFile:filePathForScreenshot atomically:YES];
            }
            numberOfScreenshots++;
            dispatch_semaphore_signal(_pixelAppendSemaphore);
        });
    });
}

- (void)finishWithPendingScreenshots {
    dispatch_queue_t finishTheJobQueue = dispatch_queue_create("q_finishIt", NULL);
    dispatch_async(finishTheJobQueue, ^{

        BOOL pendingScreenshots = YES;
        while (pendingScreenshots) {
            if (dispatch_semaphore_wait(_writeVideoSemaphore, DISPATCH_TIME_NOW) != 0) {
                NSLog(@"_writeVideoSemaphore waiting");
                [NSThread sleepForTimeInterval:0.2];
            } else {
                NSString *pendingPath = nil;
                pendingScreenshots = [self thereArePendingScreenshots:&pendingPath];
                if (!pendingScreenshots) {
                    [self mergeVideos];
                    continue;
                }
                numberOfScreenshots = 0;
                self.firstTimeStamp = 0;
                [self videoFromImages:pendingPath];
            }
        }
    });
}

- (BOOL)thereArePendingScreenshots:(NSString **)pendingPath {
    NSError *error;
    NSString *_filePath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/%@/", kScreenshotsTemporalFolder]];
    NSArray *screenshotsPath = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_filePath error:&error];
    if (error) {
        NSLog(@"Error while taking all the screenshots %@", error);
        return NO;
    } else {
        if(screenshotsPath.count > 0) {
            int i = 0;
            while (!*pendingPath && i < screenshotsPath.count) {
                if (![[screenshotsPath objectAtIndex:i] isEqualToString:@".DS_Store"] && ([[screenshotsPath objectAtIndex:i] rangeOfString:@"screenshot"].location != NSNotFound)) {
                    *pendingPath = [_filePath stringByAppendingString:[NSString stringWithFormat:@"/%@", [screenshotsPath objectAtIndex:i]]];
                }
                i++;
            }
            return (pendingPath != nil);
        }
        return NO;
    }
}

#pragma mark - Video methods
- (void)videoFromImages:(NSString *)place
{
    dispatch_async(_videoWriter_queue, ^{
        NSError *error;
        NSLog(@"video started");
        
        BOOL fileMovieExists = YES;
        while (fileMovieExists) {
            fileMovieExists = [[NSFileManager defaultManager] fileExistsAtPath:[[self videosTemporalFolder] stringByAppendingPathComponent:[NSString stringWithFormat:@"/output%ld.mp4", (long)self.videoloop]]];
            if (fileMovieExists)
                self.videoloop ++;
        }
        
        videoWriter = [[AVAssetWriter alloc] initWithURL:
                       [NSURL fileURLWithPath:[[self videosTemporalFolder] stringByAppendingPathComponent:[NSString stringWithFormat:@"/output%ld.mp4", (long)self.videoloop]]] fileType:AVFileTypeQuickTimeMovie
                                                   error:&error];
        if (!error) {
            NSParameterAssert(videoWriter);
            
            NSInteger pixelNumber = _winSize.width * _winSize.height * _scale * kVideoScale;
            NSDictionary* videoCompression = @{AVVideoAverageBitRateKey: @(pixelNumber * 11.4)};
            
            NSDictionary* videoSettings = @{AVVideoCodecKey: AVVideoCodecH264,
                                            AVVideoWidthKey: [NSNumber numberWithInt:_winSize.width*_scale * kVideoScale],
                                            AVVideoHeightKey: [NSNumber numberWithInt:_winSize.height*_scale * kVideoScale],
                                            AVVideoCompressionPropertiesKey: videoCompression};
            AVAssetWriterInput* videoWriterInput = [AVAssetWriterInput
                                                    assetWriterInputWithMediaType:AVMediaTypeVideo
                                                    outputSettings:videoSettings];
            
            
            AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
                                                             assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoWriterInput
                                                             sourcePixelBufferAttributes:nil];
            
            NSParameterAssert(videoWriterInput);
            NSParameterAssert([videoWriter canAddInput:videoWriterInput]);
            
            videoWriterInput.transform = [self videoTransformForDeviceOrientation];
            
            [videoWriter addInput:videoWriterInput];
            [videoWriter startWriting];
            [videoWriter startSessionAtSourceTime:kCMTimeZero];
            
            NSArray *images = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:(!place ? [self filesPath:YES] : place) error:&error];
            
            int i = 0;
            while (i < images.count) {
                
                NSString *imgPath = [images objectAtIndex:i];
                
                if (![[imgPath pathExtension] isEqualToString:@"png"]) {
                    i++;
                    continue;
                }
                UIImage *img = [UIImage imageWithContentsOfFile:[(!place ? [self filesPath:YES] : place) stringByAppendingFormat:@"/%@",imgPath]];
                
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
                [[NSFileManager defaultManager] removeItemAtPath:(!place ? [self filesPath:YES] : place) error:&error];
                if (error)
                    NSLog(@"error removing path: %@", error);
                
                self.videoloop++;
                NSLog(@"video finished");
                dispatch_semaphore_signal(_writeVideoSemaphore);
                NSLog(@"_writeVideoSemaphore dispatched");
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
                        kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options,
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
    dispatch_queue_t mergeQueue = dispatch_queue_create("q_mergeVideos", NULL);
    
    dispatch_async(mergeQueue, ^{
        BOOL readyToRun = (dispatch_semaphore_wait(_writeVideoSemaphore, DISPATCH_TIME_NOW) != 0) ;
        while (!readyToRun) {
            NSLog(@"_writeVideoSemaphore waiting");
            [NSThread sleepForTimeInterval:0.2];
        }
        NSLog(@"MERGE - Started");
        AVMutableComposition* composition = [[AVMutableComposition alloc] init];
        AVMutableCompositionTrack * composedTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                             preferredTrackID:kCMPersistentTrackID_Invalid];
        NSMutableArray *assets = [NSMutableArray arrayWithArray:@[]];
        NSError *error;
        
        NSArray *allVideosPath = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self videosTemporalFolder] error:&error];
        if (error) {
            NSLog(@"there was an error while getting the videos path: %@", error);
            return;
        }
        
        for (NSString *videoPath in allVideosPath) {
            if (![[videoPath pathExtension] isEqualToString:@"mp4"]) {
                continue;
            }
            
            NSString *path = [[self videosTemporalFolder] stringByAppendingFormat:@"/%@",videoPath];
            AVURLAsset *video = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
            [assets addObject:video];
        }
        
        int i = assets.count;
        if (assets.count == 0) {
            return;
        }
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
        
        composedTrack.preferredTransform = [self mergeTransform];
        
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
                    NSLog(@"Merge StatusUnknown");
                    break;
                case AVAssetExportSessionStatusWaiting:
                    NSLog(@"Merge Waiting");
                    break;
                case AVAssetExportSessionStatusExporting:
                    NSLog(@"Merge Exporting");
                    break;
                case AVAssetExportSessionStatusCompleted:
                {
                    NSError *fsError;
                    [[NSFileManager defaultManager] removeItemAtPath:[self videosTemporalFolder] error:&fsError];
                    if (fsError) {
                        NSLog(@"Error while removing the videos temporal folder: %@", fsError);
                    }
                    NSLog(@"Merge Completed");
                    dispatch_async(dispatch_get_main_queue(), ^{
                        videoWriter = nil;
                    });
                    break;
                }
                case AVAssetExportSessionStatusFailed:
                    NSLog(@"Merge Failed");
                    break;
                case AVAssetExportSessionStatusCancelled:
                    NSLog(@"Merge Cancelled");
                    break;
                default:
                    NSLog(@"Merge unknown");
                    break;
            }
            
        }];
        
    });
}

- (CGAffineTransform)mergeTransform {
    // Rotate 45 degrees
    CGAffineTransform rotate = [self videoTransformForDeviceOrientation];
    // Move to the left
    CGAffineTransform scale  = CGAffineTransformMakeScale(0.1, 0.1);
    // Apply them to a view
    return CGAffineTransformConcat(rotate, scale);
}



- (CGAffineTransform)videoTransformForDeviceOrientation
{
    CGAffineTransform videoTransform;
    switch ([[UIApplication sharedApplication] statusBarOrientation]) {
        case UIDeviceOrientationLandscapeLeft:
            videoTransform = CGAffineTransformMakeRotation(-M_PI_2);
            break;
        case UIDeviceOrientationLandscapeRight:
            videoTransform = CGAffineTransformMakeRotation(M_PI_2);
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            videoTransform = CGAffineTransformMakeRotation(M_PI);
            break;
        default:
            videoTransform = CGAffineTransformIdentity;
    }
    return videoTransform;
}



@end

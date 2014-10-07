//
//  GPScreenVideoRecording.h
//  ScreenVideoRecording
//
//  Created by German Pereyra on 10/6/14.
//
//

#import <Foundation/Foundation.h>

@interface GPScreenVideoRecording : NSObject
- (void)startCapturing;
- (void)stopCapturing;
- (void)mergeVideos;;
- (void)finishWithPendingScreenshots;
- (BOOL)thereArePendingScreenshots:(NSString **)pendingPath;
@end

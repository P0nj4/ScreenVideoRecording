//
//  GPScreenVideoRecording.h
//  ScreenVideoRecording
//
//  Created by German Pereyra on 10/6/14.
//
//

#import <Foundation/Foundation.h>

@interface GPScreenVideoRecording : NSObject
@property (nonatomic, strong) NSString *videoName;
- (void)startCapturing;
- (void)stopCapturing;
- (void)merge ;
@end

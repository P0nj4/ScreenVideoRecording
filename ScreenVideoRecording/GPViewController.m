//
//  GPViewController.m
//  ScreenVideoRecording
//
//  Created by German Pereyra on 10/6/14.
//
//

#import "GPViewController.h"
#import "GPScreenVideoRecording.h"

@interface GPViewController ()
- (IBAction)StopRecording:(id)sender;
- (IBAction)startRecording:(id)sender;
@property (nonatomic, strong) GPScreenVideoRecording *recorder;
@end

@implementation GPViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    self.recorder = [[GPScreenVideoRecording alloc] init];
    //[self.recorder startCapturing];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)StopRecording:(id)sender {
    
    [self.recorder stopCapturing];
}

- (IBAction)startRecording:(id)sender {
    [self.recorder startCapturing];
}
@end
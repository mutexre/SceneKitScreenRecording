//
//  GameViewController.m
//  IOS SCN ScreenRecording
//
//  Created by mutexre on 19/08/16.
//  Copyright (c) 2016 mutexre. All rights reserved.
//

#import "GameViewController.h"
#import <OpenGLES/ES3/gl.h>
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <Photos/Photos.h>

@implementation GameViewController {
    AVAssetWriter* assetWriter;
    AVAssetWriterInput* assetWriterInput;
    AVAssetWriterInputPixelBufferAdaptor* writerInputBufferAdaptor;
    NSURL* movieUrl;
    OSType pixelFormat;
    size_t bytesPerRow;
    
    struct {
        NSInteger width, height;
        char* buf[2];
    }
    frame;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // create a new scene
    SCNScene *scene = [SCNScene sceneNamed:@"art.scnassets/ship.scn"];

    // create and add a camera to the scene
    SCNNode *cameraNode = [SCNNode node];
    cameraNode.camera = [SCNCamera camera];
    [scene.rootNode addChildNode:cameraNode];
    
    // place the camera
    cameraNode.position = SCNVector3Make(0, 0, 15);
    
    // create and add a light to the scene
    SCNNode *lightNode = [SCNNode node];
    lightNode.light = [SCNLight light];
    lightNode.light.type = SCNLightTypeOmni;
    lightNode.position = SCNVector3Make(0, 10, 10);
    [scene.rootNode addChildNode:lightNode];
    
    // create and add an ambient light to the scene
    SCNNode *ambientLightNode = [SCNNode node];
    ambientLightNode.light = [SCNLight light];
    ambientLightNode.light.type = SCNLightTypeAmbient;
    ambientLightNode.light.color = [UIColor darkGrayColor];
    [scene.rootNode addChildNode:ambientLightNode];
    
    // retrieve the ship node
    SCNNode *ship = [scene.rootNode childNodeWithName:@"ship" recursively:YES];
    
    // animate the 3d object
    [ship runAction:[SCNAction repeatActionForever:[SCNAction rotateByX:0 y:2 z:0 duration:1]]];
    
    // retrieve the SCNView
    SCNView *scnView = (SCNView *)self.view;
    
    scnView.delegate = self;
    
    // set the scene to the view
    scnView.scene = scene;
    
    // allows the user to manipulate the camera
    scnView.allowsCameraControl = YES;
    
    // show statistics such as fps and timing information
    scnView.showsStatistics = YES;
    
    // configure the view
    scnView.backgroundColor = [UIColor blackColor];
    
    // add a tap gesture recognizer
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    NSMutableArray *gestureRecognizers = [NSMutableArray array];
    [gestureRecognizers addObject:tapGesture];
    [gestureRecognizers addObjectsFromArray:scnView.gestureRecognizers];
    scnView.gestureRecognizers = gestureRecognizers;
    
    scnView.contentScaleFactor = 1;
    int scale = scnView.contentScaleFactor;
    frame.width = scale * scnView.bounds.size.width;
    frame.height = scale * scnView.bounds.size.height;
    
    for (int i = 0; i < 2; i++)
        frame.buf[i] = malloc(frame.width * frame.height * 4);
    
    if (![self startRecording])
        NSLog(@"failed to start recording video");
    
    NSNotificationCenter* defaultCenter = [NSNotificationCenter defaultCenter];
    [defaultCenter addObserver:self
                      selector:@selector(applicationWillTerminate:)
                          name:UIApplicationWillTerminateNotification
                        object:nil];
}

- (BOOL)startRecording
{
    pixelFormat = kCVPixelFormatType_32BGRA;
    bytesPerRow = 4 * frame.width;
    
    NSString* movieFileName = [NSString stringWithFormat:@"%@.mov", [NSUUID UUID].UUIDString];
    NSString* moviePath = [NSTemporaryDirectory() stringByAppendingPathComponent:movieFileName];
    movieUrl = [NSURL fileURLWithPath:moviePath];
    
    NSError* error = nil;
    assetWriter = [AVAssetWriter assetWriterWithURL:movieUrl
                                           fileType:AVFileTypeQuickTimeMovie
                                              error:&error];
    if (!assetWriter) {
        NSLog(@"failed to create asset writer: %@", error.description);
        return NO;
    }
    
    NSDictionary* videoSettings = @{
        AVVideoCodecKey: AVVideoCodecH264,
        AVVideoWidthKey: @(frame.width),
        AVVideoHeightKey: @(frame.height)
    };
    
    assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                     outputSettings:videoSettings];
    if (!assetWriterInput) {
        NSLog(@"failed to create asset writer input");
        return NO;
    }
    
    if (![assetWriter canAddInput:assetWriterInput]) {
        NSLog(@"can not add input to asset writer");
        return NO;
    }
    
    [assetWriter addInput:assetWriterInput];
    
    NSDictionary* bufferAttributes = @{
        (__bridge NSString*)kCVPixelBufferPixelFormatTypeKey : @(pixelFormat)
    };
    
    writerInputBufferAdaptor = [[AVAssetWriterInputPixelBufferAdaptor alloc] initWithAssetWriterInput:assetWriterInput
                                                                          sourcePixelBufferAttributes:bufferAttributes];
    if (!writerInputBufferAdaptor) {
        NSLog(@"failed to create input buffer adapter");
        return NO;
    }
    
    if ([assetWriter startWriting])
        [assetWriter startSessionAtSourceTime:/*CMTimeMake(0, 600)*/kCMTimeZero];
    else {
        NSLog(@"failed to start writing: %ld %@", (long)assetWriter.status, assetWriter.error.description);
        return NO;
    }
    
    return YES;
}

- (void)dealloc
{
    for (int i = 0; i < 2; i++) {
        if (frame.buf[i])
            free(frame.buf[i]);
    }
}

/*- (void)applicationWillTerminate:(id)sender {
    [writerInput markAsFinished];
    [videoWriter finishWritingWithCompletionHandler:^{
        NSLog(@"finished writing");
        [self saveVideoToLibrary:movieUrl];
    }];
}*/

- (void) handleTap:(UIGestureRecognizer*)gestureRecognize
{
    // retrieve the SCNView
    SCNView *scnView = (SCNView *)self.view;
    
    // check what nodes are tapped
    CGPoint p = [gestureRecognize locationInView:scnView];
    NSArray *hitResults = [scnView hitTest:p options:nil];
    
    // check that we clicked on at least one object
    if([hitResults count] > 0){
        // retrieved the first clicked object
        SCNHitTestResult *result = [hitResults objectAtIndex:0];
        
        // get its material
        SCNMaterial *material = result.node.geometry.firstMaterial;
        
        // highlight it
        [SCNTransaction begin];
        [SCNTransaction setAnimationDuration:0.5];
        
        // on completion - unhighlight
        [SCNTransaction setCompletionBlock:^{
            [SCNTransaction begin];
            [SCNTransaction setAnimationDuration:0.5];
            
            material.emission.contents = [UIColor blackColor];
            
            [SCNTransaction commit];
        }];
        
        material.emission.contents = [UIColor redColor];
        
        [SCNTransaction commit];
    }
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    } else {
        return UIInterfaceOrientationMaskAll;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark SCNSceneRendererDelegate

#define FRAMES_N (30 * 15)

- (void)renderer:(id <SCNSceneRenderer>)renderer didRenderScene:(SCNScene *)scene atTime:(NSTimeInterval)time
{
    static int frameIndex = 0;
    
    if (frameIndex < FRAMES_N) {
        if (![self recordFrame:frameIndex])
            NSLog(@"failed to record frame");
    }
    
    frameIndex++;
    
    if (frameIndex == FRAMES_N)
    {
        [assetWriterInput markAsFinished];
        [assetWriter finishWritingWithCompletionHandler:^{
            NSLog(@"finished writing");
            [self saveVideoToLibrary:movieUrl];
        }];
    }
}

- (BOOL)processImage
{
    vImage_Buffer src, dst;
    
    src.width = dst.width = frame.width;
    src.height = dst.height = frame.height;
    src.rowBytes = dst.rowBytes = 4 * frame.width;
    src.data = frame.buf[0];
    dst.data = frame.buf[1];

    const uint8_t map[4] = { 2, 1, 0, 3 };
    vImage_Error result = vImagePermuteChannels_ARGB8888(&src, &dst, map, kvImageNoFlags);
    if (result != kvImageNoError) {
        NSLog(@"failed to convert pixel format (status code = %ld)", result);
        return NO;
    }
    
    result = vImageVerticalReflect_ARGB8888(&dst, &src, kvImageNoFlags);
    if (result != kvImageNoError) {
        NSLog(@"failed to flip image vertically (status code = %ld)", result);
        return NO;
    }
    
    return YES;
}

- (BOOL)recordFrame:(int)frameIndex
{
    SCNView* view = (SCNView*)self.view;
    
    [EAGLContext setCurrentContext:view.eaglContext];
    
    glReadPixels(0, 0, (GLsizei)frame.width, (GLsizei)frame.height, GL_RGBA, GL_UNSIGNED_BYTE, frame.buf[0]);

    if (![self processImage]) {
        NSLog(@"failed to process image");
        return NO;
    }

    if (assetWriterInput.readyForMoreMediaData)
    {
        NSLog(@"video writer status: %ld", (long)assetWriter.status);
        
        CVPixelBufferRef pixelBuffer = NULL;
        
        CVReturn result =
            CVPixelBufferCreateWithBytes(kCFAllocatorDefault,
                                         frame.width, frame.height,
                                         pixelFormat,
                                         frame.buf[0],
                                         4 * frame.width,
                                         NULL, NULL,
                                         NULL,
                                         &pixelBuffer);
        if (result || !pixelBuffer) {
            NSLog(@"failed to create pixel buffer (status code = %d)", result);
            return NO;
        }
        
        if (![writerInputBufferAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:CMTimeMake(frameIndex * 20, 600)]) {
            NSLog(@"failed to append sample buffer: %@", assetWriter.error.description);
            return NO;
        }
    }
    else {
        NSLog(@"video writer input is not ready for more data");
        return NO;
    }
    
    return YES;
}

/*- (CMSampleBufferRef)newPixelBufferFromImageData:(void*)data
                                           width:(size_t)width
                                          height:(size_t)height
                                      frameIndex:(int)frameIndex
                                     pixelFormat:(OSType)pixelFormat
                                     bytesPerRow:(int)bytesPerRow
{
    CVPixelBufferRef pixelBuffer = NULL;

    CVReturn result =
        CVPixelBufferCreateWithBytes(kCFAllocatorDefault,
                                     width, height,
                                     pixelFormat,
                                     data,
                                     bytesPerRow,
                                     NULL, NULL,
                                     NULL,
                                     &pixelBuffer);
    if (!result && pixelBuffer)
    {
        CMSampleTimingInfo timing;
        
        timing.duration = CMTimeMake(20, 600);
        timing.presentationTimeStamp = CMTimeMake(frameIndex * 20, 600);
        timing.decodeTimeStamp = timing.presentationTimeStamp;
        
        CMVideoFormatDescriptionRef format = NULL;
        OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &format);
        if (!status && format)
        {
            CMSampleBufferRef sampleBuffer = NULL;
            status = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
                                                              pixelBuffer,
                                                              format,
                                                              &timing,
                                                              &sampleBuffer);
            //CVPixelBufferRelease(pixelBuffer);
            
            return sampleBuffer;
        }
        else
            NSLog(@"failed to create sample buffer (status code = %d)", result);
    }
    else
        NSLog(@"failed to create pixel buffer (status code = %d)", result);
    
    return NULL;
}*/

- (void)saveVideoToLibrary:(NSURL*)videoURL
{
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            NSLog(@"failed to authorize Photo library access\n");
        }
        else {
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                PHAssetChangeRequest* request = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:videoURL];
                if (!request)
                    NSLog(@"failed to create change request");
            }
            completionHandler:^(BOOL success, NSError* error) {
                if (!success) {
                    NSLog(@"failed to add movie to Photos library: %@", error.description);
                }
            }];
        }
    }];
}

@end

//
//  ViewController.m
//  Starface
//
//  Created by Johan Mathe on 3/2/15.
//  Copyright (c) 2015 starface. All rights reserved.
//

#import "ViewController.h"
#include "PhotoViewController.h"
#import "ConvnetClassifier.h"

#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <AssertMacros.h>
#import <AssetsLibrary/AssetsLibrary.h>

#import "ccv.h"
#pragma mark -

// used for KVO observation of the @"capturingStillImage" property to perform
// flash bulb animation
static const NSString *AVCaptureStillImageIsCapturingStillImageContext = @"AVCaptureStillImageIsCapturingStillImageContext";

static CGFloat DegreesToRadians(CGFloat degrees) { return degrees * M_PI / 180; };

static void ReleaseCVPixelBuffer(void *pixel, const void *data, size_t size);
static void ReleaseCVPixelBuffer(void *pixel, const void *data, size_t size) {
  CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)pixel;
  CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
  CVPixelBufferRelease(pixelBuffer);
}

// create a CGImage with provided pixel buffer, pixel buffer must be
// uncompressed kCVPixelFormatType_32ARGB or kCVPixelFormatType_32BGRA
static OSStatus CreateCGImageFromCVPixelBuffer(CVPixelBufferRef pixelBuffer, CGImageRef *imageOut);
static OSStatus CreateCGImageFromCVPixelBuffer(CVPixelBufferRef pixelBuffer, CGImageRef *imageOut) {
  OSStatus err = noErr;
  OSType sourcePixelFormat;
  size_t width, height, sourceRowBytes;
  void *sourceBaseAddr = NULL;
  CGBitmapInfo bitmapInfo;
  CGColorSpaceRef colorspace = NULL;
  CGDataProviderRef provider = NULL;
  CGImageRef image = NULL;

  sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
  if (kCVPixelFormatType_32ARGB == sourcePixelFormat)
    bitmapInfo = kCGBitmapByteOrder32Big | kCGImageAlphaNoneSkipFirst;
  else if (kCVPixelFormatType_32BGRA == sourcePixelFormat)
    bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst;
  else
    return -95014;  // only uncompressed pixel formats

  sourceRowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer);
  width = CVPixelBufferGetWidth(pixelBuffer);
  height = CVPixelBufferGetHeight(pixelBuffer);

  CVPixelBufferLockBaseAddress(pixelBuffer, 0);
  sourceBaseAddr = CVPixelBufferGetBaseAddress(pixelBuffer);

  colorspace = CGColorSpaceCreateDeviceRGB();

  CVPixelBufferRetain(pixelBuffer);
  provider = CGDataProviderCreateWithData((void *)pixelBuffer, sourceBaseAddr, sourceRowBytes * height, ReleaseCVPixelBuffer);
  image = CGImageCreate(width, height, 8, 32, sourceRowBytes, colorspace, bitmapInfo, provider, NULL, true, kCGRenderingIntentDefault);

bail:
  if (err && image) {
    CGImageRelease(image);
    image = NULL;
  }
  if (provider) CGDataProviderRelease(provider);
  if (colorspace) CGColorSpaceRelease(colorspace);
  *imageOut = image;
  return err;
}

// utility used by newSquareOverlayedImageForFeatures for
static CGContextRef CreateCGBitmapContextForSize(CGSize size);
static CGContextRef CreateCGBitmapContextForSize(CGSize size) {
  CGContextRef context = NULL;
  CGColorSpaceRef colorSpace;
  int bitmapBytesPerRow;

  bitmapBytesPerRow = (size.width * 4);

  colorSpace = CGColorSpaceCreateDeviceRGB();
  context = CGBitmapContextCreate(NULL, size.width, size.height,
                                  8,  // bits per component
                                  bitmapBytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast);
  CGContextSetAllowsAntialiasing(context, NO);
  CGColorSpaceRelease(colorSpace);
  return context;
}

#pragma mark -

@interface UIImage (RotationMethods)
- (UIImage *)imageRotatedByDegrees:(CGFloat)degrees;
@end

@implementation UIImage (RotationMethods)

- (UIImage *)imageRotatedByDegrees:(CGFloat)degrees {
  // calculate the size of the rotated view's containing box for our drawing
  // space
  UIView *rotatedViewBox = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.size.width, self.size.height)];
  CGAffineTransform t = CGAffineTransformMakeRotation(DegreesToRadians(degrees));
  rotatedViewBox.transform = t;
  CGSize rotatedSize = rotatedViewBox.frame.size;
  [rotatedViewBox release];

  // Create the bitmap context
  UIGraphicsBeginImageContext(rotatedSize);
  CGContextRef bitmap = UIGraphicsGetCurrentContext();

  // Move the origin to the middle of the image so we will rotate and scale
  // around the center.
  CGContextTranslateCTM(bitmap, rotatedSize.width / 2, rotatedSize.height / 2);

  //   // Rotate the image context
  CGContextRotateCTM(bitmap, DegreesToRadians(degrees));

  // Now, draw the rotated/scaled image into the context
  CGContextScaleCTM(bitmap, 1.0, -1.0);
  CGContextDrawImage(bitmap, CGRectMake(-self.size.width / 2, -self.size.height / 2, self.size.width, self.size.height), [self CGImage]);

  UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return newImage;
}

@end

#pragma mark -

@interface ViewController (InternalMethods)
- (void)setupAVCapture;
- (void)teardownAVCapture;
- (void)drawFaceBoxesForFeatures:(NSArray *)features forVideoBox:(CGRect)clap orientation:(UIDeviceOrientation)orientation;
@end

@implementation ViewController

- (void)setupAVCapture {
  NSError *error = nil;

  AVCaptureSession *session = [AVCaptureSession new];
  if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    [session setSessionPreset:AVCaptureSessionPreset640x480];
  else
    [session setSessionPreset:AVCaptureSessionPresetPhoto];

  // Select a video device, make an input
  AVCaptureDevice *frontDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
  NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
  for (AVCaptureDevice *device in devices) {
    if ([device position] == AVCaptureDevicePositionFront) {
      frontDevice = device;
    }
  }

  AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:frontDevice error:&error];
  require(error == nil, bail);

  isUsingFrontFacingCamera = YES;
  if ([session canAddInput:deviceInput]) [session addInput:deviceInput];

  // Make a still image output
  stillImageOutput = [AVCaptureStillImageOutput new];
  [stillImageOutput addObserver:self forKeyPath:@"capturingStillImage" options:NSKeyValueObservingOptionNew context:AVCaptureStillImageIsCapturingStillImageContext];
  if ([session canAddOutput:stillImageOutput]) [session addOutput:stillImageOutput];

  // Make a video data output
  videoDataOutput = [AVCaptureVideoDataOutput new];

  // we want BGRA, both CoreGraphics and OpenGL work well with 'BGRA'
  NSDictionary *rgbOutputSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCMPixelFormat_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
  [videoDataOutput setVideoSettings:rgbOutputSettings];
  [videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];  // discard if the
                                                           // data output queue
                                                           // is blocked (as we
                                                           // process the still
                                                           // image)

  // create a serial dispatch queue used for the sample buffer delegate as well
  // as when a still image is captured
  // a serial dispatch queue must be used to guarantee that video frames will be
  // delivered in order
  // see the header doc for setSampleBufferDelegate:queue: for more information
  videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
  [videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];

  if ([session canAddOutput:videoDataOutput]) [session addOutput:videoDataOutput];
  [[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:NO];

  effectiveScale = 1.0;
  previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
  [previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
  [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
  CALayer *rootLayer = [previewView layer];
  [rootLayer setMasksToBounds:YES];
  [previewLayer setFrame:[mainView frame]];
  [rootLayer addSublayer:previewLayer];
  [session startRunning];
  [[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:detectFaces];

bail:
  [session release];
  if (error) {
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"Failed with error %d", (int)[error code]]
                                                        message:[error localizedDescription]
                                                       delegate:nil
                                              cancelButtonTitle:@"Dismiss"
                                              otherButtonTitles:nil];
    [alertView show];
    [alertView release];
    [self teardownAVCapture];
  }
}

// clean up capture setup
- (void)teardownAVCapture {
  [videoDataOutput release];
  if (videoDataOutputQueue) dispatch_release(videoDataOutputQueue);
  [stillImageOutput removeObserver:self forKeyPath:@"isCapturingStillImage"];
  [stillImageOutput release];
  [previewLayer removeFromSuperlayer];
  [previewLayer release];
}

// perform a flash bulb animation using KVO to monitor the value of the
// capturingStillImage property of the AVCaptureStillImageOutput class
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
  if (context == AVCaptureStillImageIsCapturingStillImageContext) {
    BOOL isCapturingStillImage = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];

    if (isCapturingStillImage) {
      // do flash bulb like animation
      flashView = [[UIView alloc] initWithFrame:[previewView frame]];
      [flashView setBackgroundColor:[UIColor whiteColor]];
      [flashView setAlpha:0.f];
      [[[self view] window] addSubview:flashView];

      [UIView animateWithDuration:0.1f animations:^{ [flashView setAlpha:1.f]; }];
    } else {
      [UIView animateWithDuration:0.1f
          animations:^{ [flashView setAlpha:0.f]; }
          completion:^(BOOL finished) {
              [flashView removeFromSuperview];
              [flashView release];
              flashView = nil;
          }];
    }
  }
}

// utility routing used during image capture to set up capture orientation
- (AVCaptureVideoOrientation)avOrientationForDeviceOrientation:(UIDeviceOrientation)deviceOrientation {
  AVCaptureVideoOrientation result = deviceOrientation;
  if (deviceOrientation == UIDeviceOrientationLandscapeLeft)
    result = AVCaptureVideoOrientationLandscapeRight;
  else if (deviceOrientation == UIDeviceOrientationLandscapeRight)
    result = AVCaptureVideoOrientationLandscapeLeft;
  return result;
}

// utility routine to create a new image with the red square overlay with
// appropriate orientation
// and return the new composited image which can be saved to the camera roll
- (CGImageRef)newSquareOverlayedImageForFeatures:(NSArray *)features inCGImage:(CGImageRef)backgroundImage withOrientation:(UIDeviceOrientation)orientation frontFacing:(BOOL)isFrontFacing {
  CGImageRef returnImage = NULL;
  CGRect backgroundImageRect = CGRectMake(0., 0., CGImageGetWidth(backgroundImage), CGImageGetHeight(backgroundImage));
  CGContextRef bitmapContext = CreateCGBitmapContextForSize(backgroundImageRect.size);
  CGContextClearRect(bitmapContext, backgroundImageRect);
  CGContextDrawImage(bitmapContext, backgroundImageRect, backgroundImage);
  CGFloat rotationDegrees = 0.;

  switch (orientation) {
    case UIDeviceOrientationPortrait:
      rotationDegrees = -90.;
      break;
    case UIDeviceOrientationPortraitUpsideDown:
      rotationDegrees = 90.;
      break;
    case UIDeviceOrientationLandscapeLeft:
      if (isFrontFacing)
        rotationDegrees = 180.;
      else
        rotationDegrees = 0.;
      break;
    case UIDeviceOrientationLandscapeRight:
      if (isFrontFacing)
        rotationDegrees = 0.;
      else
        rotationDegrees = 180.;
      break;
    case UIDeviceOrientationFaceUp:
    case UIDeviceOrientationFaceDown:
    default:
      break;  // leave the layer in its last known orientation
  }
  UIImage *rotatedSquareImage = [square imageRotatedByDegrees:rotationDegrees];

  // features found by the face detector
  for (CIFaceFeature *ff in features) {
    CGRect faceRect = [ff bounds];
    faceRect.origin.y = backgroundImageRect.origin.y + backgroundImageRect.size.height - (faceRect.origin.y + faceRect.size.height);
    CGContextDrawImage(bitmapContext, faceRect, [rotatedSquareImage CGImage]);
    returnImage = CGBitmapContextCreateImage(bitmapContext);
    CGContextRelease(bitmapContext);
    return CGImageCreateWithImageInRect(returnImage, faceRect);
  }

  return returnImage;
}

- (CGImageRef)CGImageRotatedByAngle:(CGImageRef)imgRef angle:(CGFloat)angle {
  CGFloat angleInRadians = angle * (M_PI / 180);
  CGFloat width = CGImageGetWidth(imgRef);
  CGFloat height = CGImageGetHeight(imgRef);

  CGRect imgRect = CGRectMake(0, 0, width, height);
  CGAffineTransform transform = CGAffineTransformMakeRotation(angleInRadians);
  CGRect rotatedRect = CGRectApplyAffineTransform(imgRect, transform);

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef bmContext = CGBitmapContextCreate(NULL, rotatedRect.size.width, rotatedRect.size.height, 8, 0, colorSpace, kCGImageAlphaPremultipliedFirst);
  CGContextSetAllowsAntialiasing(bmContext, YES);
  CGContextSetInterpolationQuality(bmContext, kCGInterpolationHigh);
  CGColorSpaceRelease(colorSpace);
  CGContextTranslateCTM(bmContext, +(rotatedRect.size.width / 2), +(rotatedRect.size.height / 2));
  CGContextRotateCTM(bmContext, angleInRadians);
  CGContextDrawImage(bmContext, CGRectMake(-width / 2, -height / 2, width, height), imgRef);

  CGImageRef rotatedImage = CGBitmapContextCreateImage(bmContext);
  CFRelease(bmContext);
  [(id)rotatedImage autorelease];

  return rotatedImage;
}

// utility routine to display error aleart if takePicture fails
- (void)displayErrorOnMainQueue:(NSError *)error withMessage:(NSString *)message {
  dispatch_async(dispatch_get_main_queue(), ^(void) {
      UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"%@ (%d)", message, (int)[error code]]
                                                          message:[error localizedDescription]
                                                         delegate:nil
                                                cancelButtonTitle:@"Dismiss"
                                                otherButtonTitles:nil];
      [alertView show];
      [alertView release];
  });
}

- (IBAction)starfaceButtonClicked:(id)sender {
  // Find out the current orientation and tell the still image output.
  AVCaptureConnection *stillImageConnection = [stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
  UIDeviceOrientation curDeviceOrientation = [[UIDevice currentDevice] orientation];
  AVCaptureVideoOrientation avcaptureOrientation = [self avOrientationForDeviceOrientation:curDeviceOrientation];
  [stillImageConnection setVideoOrientation:avcaptureOrientation];
  [stillImageConnection setVideoScaleAndCropFactor:effectiveScale];

  // set the appropriate pixel format / image type output setting depending on
  // if we'll need an uncompressed image for
  // the possiblity of drawing the red square over top or if we're just writing
  // a jpeg to the camera roll which is the trival case
  if (true)
    [stillImageOutput setOutputSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCMPixelFormat_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
  else
    [stillImageOutput setOutputSettings:[NSDictionary dictionaryWithObject:AVVideoCodecJPEG forKey:AVVideoCodecKey]];

  [stillImageOutput
      captureStillImageAsynchronouslyFromConnection:stillImageConnection
                                  completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
                                      if (error) {
                                        [self displayErrorOnMainQueue:error withMessage:@"Take picture failed"];
                                      } else {
                                        if (true) {
                                          // Got an image.
                                          CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(imageDataSampleBuffer);
                                          CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, imageDataSampleBuffer, kCMAttachmentMode_ShouldPropagate);
                                          CIImage *ciImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer options:(NSDictionary *)attachments];
                                          if (attachments) CFRelease(attachments);

                                          NSDictionary *imageOptions = nil;
                                          NSNumber *orientation = CMGetAttachment(imageDataSampleBuffer, kCGImagePropertyOrientation, NULL);
                                          if (orientation) {
                                            imageOptions = [NSDictionary dictionaryWithObject:orientation forKey:CIDetectorImageOrientation];
                                          }

                                          // when processing an existing frame we want any new frames to
                                          // be automatically dropped
                                          // queueing this block to execute on the videoDataOutputQueue
                                          // serial queue ensures this
                                          // see the header doc for setSampleBufferDelegate:queue: for
                                          // more information
                                          dispatch_sync(videoDataOutputQueue, ^(void) {

                                              // get the array of CIFeature instances in the given image
                                              // with a orientation passed in
                                              // the detection will be done based on the orientation but
                                              // the coordinates in the returned features will
                                              // still be based on those of the image.
                                              NSArray *features = [faceDetector featuresInImage:ciImage options:imageOptions];
                                              if (features.count == 0) {
                                                textView.text = @"No face found!";
                                              } else {
                                                textView.text = @"";
                                                CGImageRef srcImage = NULL;
                                                OSStatus err = CreateCGImageFromCVPixelBuffer(CMSampleBufferGetImageBuffer(imageDataSampleBuffer), &srcImage);
                                                check(!err);

                                                CGImageRef cgImageResult =
                                                    [self newSquareOverlayedImageForFeatures:features inCGImage:srcImage withOrientation:curDeviceOrientation frontFacing:isUsingFrontFacingCamera];
                                                if (srcImage) CFRelease(srcImage);

                                                CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, imageDataSampleBuffer, kCMAttachmentMode_ShouldPropagate);

                                                PhotoViewController *photoController =
                                                    [PhotoViewController createPhotoViewController:convnetClassifier artists:artistsData attachments:attachments pic:cgImageResult men:men];
                                                [self.navigationController pushViewController:photoController animated:YES];
                                              }

                                          });

                                          [ciImage release];
                                        } else {
                                          // trivial simple JPEG case
                                          NSData *jpegData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
                                          CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, imageDataSampleBuffer, kCMAttachmentMode_ShouldPropagate);
                                          ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
                                          [library writeImageDataToSavedPhotosAlbum:jpegData
                                                                           metadata:(id)attachments
                                                                    completionBlock:^(NSURL *assetURL, NSError *error) {
                                                                        if (error) {
                                                                          [self displayErrorOnMainQueue:error withMessage:@"Save to " @"camera " @"roll " @"failed"];
                                                                        }
                                                                    }];

                                          if (attachments) CFRelease(attachments);
                                          [library release];
                                        }
                                      }
                                  }];
}

// main action method to take a still image -- if face detection has been turned
// on and a face has been detected
// the square overlay will be composited on top of the captured image and saved
// to the camera roll
- (IBAction)takePicture:(id)sender {
  // Find out the current orientation and tell the still image output.
  AVCaptureConnection *stillImageConnection = [stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
  UIDeviceOrientation curDeviceOrientation = [[UIDevice currentDevice] orientation];
  AVCaptureVideoOrientation avcaptureOrientation = [self avOrientationForDeviceOrientation:curDeviceOrientation];
  [stillImageConnection setVideoOrientation:avcaptureOrientation];
  [stillImageConnection setVideoScaleAndCropFactor:effectiveScale];

  // set the appropriate pixel format / image type output setting depending on
  // if we'll need an uncompressed image for
  // the possiblity of drawing the red square over top or if we're just writing
  // a jpeg to the camera roll which is the trival case
  if (true)
    [stillImageOutput setOutputSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCMPixelFormat_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
  else
    [stillImageOutput setOutputSettings:[NSDictionary dictionaryWithObject:AVVideoCodecJPEG forKey:AVVideoCodecKey]];

  [stillImageOutput
      captureStillImageAsynchronouslyFromConnection:stillImageConnection
                                  completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
                                      if (error) {
                                        [self displayErrorOnMainQueue:error withMessage:@"Take picture failed"];
                                      } else {
                                        if (true) {
                                          // Got an image.
                                          CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(imageDataSampleBuffer);
                                          CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, imageDataSampleBuffer, kCMAttachmentMode_ShouldPropagate);
                                          CIImage *ciImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer options:(NSDictionary *)attachments];
                                          if (attachments) CFRelease(attachments);

                                          NSDictionary *imageOptions = nil;
                                          NSNumber *orientation = CMGetAttachment(imageDataSampleBuffer, kCGImagePropertyOrientation, NULL);
                                          if (orientation) {
                                            imageOptions = [NSDictionary dictionaryWithObject:orientation forKey:CIDetectorImageOrientation];
                                          }

                                          // when processing an existing frame we want any new frames to
                                          // be automatically dropped
                                          // queueing this block to execute on the videoDataOutputQueue
                                          // serial queue ensures this
                                          // see the header doc for setSampleBufferDelegate:queue: for
                                          // more information
                                          dispatch_sync(videoDataOutputQueue, ^(void) {

                                              // get the array of CIFeature instances in the given image
                                              // with a orientation passed in
                                              // the detection will be done based on the orientation but
                                              // the coordinates in the returned features will
                                              // still be based on those of the image.
                                              NSArray *features = [faceDetector featuresInImage:ciImage options:imageOptions];
                                              if (features.count == 0) {
                                                textView.text = @"No face detected, please use the " @"white oval to take a shot of your " @"face!";
                                              } else {
                                                textView.text = @"Face found!";
                                                CGImageRef srcImage = NULL;
                                                OSStatus err = CreateCGImageFromCVPixelBuffer(CMSampleBufferGetImageBuffer(imageDataSampleBuffer), &srcImage);
                                                check(!err);

                                                CGImageRef cgImageResult =
                                                    [self newSquareOverlayedImageForFeatures:features inCGImage:srcImage withOrientation:curDeviceOrientation frontFacing:isUsingFrontFacingCamera];
                                                if (srcImage) CFRelease(srcImage);

                                                CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, imageDataSampleBuffer, kCMAttachmentMode_ShouldPropagate);
                                                [self writeCGImageToCameraRoll:cgImageResult withMetadata:(id)attachments];
                                                if (attachments) CFRelease(attachments);
                                                if (cgImageResult) CFRelease(cgImageResult);
                                              }

                                          });

                                          [ciImage release];
                                        } else {
                                          // trivial simple JPEG case
                                          NSData *jpegData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
                                          CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, imageDataSampleBuffer, kCMAttachmentMode_ShouldPropagate);
                                          ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
                                          [library writeImageDataToSavedPhotosAlbum:jpegData
                                                                           metadata:(id)attachments
                                                                    completionBlock:^(NSURL *assetURL, NSError *error) {
                                                                        if (error) {
                                                                          [self displayErrorOnMainQueue:error withMessage:@"Save to " @"camera " @"roll " @"failed"];
                                                                        }
                                                                    }];

                                          if (attachments) CFRelease(attachments);
                                          [library release];
                                        }
                                      }
                                  }];
}

// find where the video box is positioned within the preview layer based on the
// video size and gravity
+ (CGRect)videoPreviewBoxForGravity:(NSString *)gravity frameSize:(CGSize)frameSize apertureSize:(CGSize)apertureSize {
  CGFloat apertureRatio = apertureSize.height / apertureSize.width;
  CGFloat viewRatio = frameSize.width / frameSize.height;

  CGSize size = CGSizeZero;
  if ([gravity isEqualToString:AVLayerVideoGravityResizeAspectFill]) {
    if (viewRatio > apertureRatio) {
      size.width = frameSize.width;
      size.height = apertureSize.width * (frameSize.width / apertureSize.height);
    } else {
      size.width = apertureSize.height * (frameSize.height / apertureSize.width);
      size.height = frameSize.height;
    }
  } else if ([gravity isEqualToString:AVLayerVideoGravityResizeAspect]) {
    if (viewRatio > apertureRatio) {
      size.width = apertureSize.height * (frameSize.height / apertureSize.width);
      size.height = frameSize.height;
    } else {
      size.width = frameSize.width;
      size.height = apertureSize.width * (frameSize.width / apertureSize.height);
    }
  } else if ([gravity isEqualToString:AVLayerVideoGravityResize]) {
    size.width = frameSize.width;
    size.height = frameSize.height;
  }

  CGRect videoBox;
  videoBox.size = size;
  if (size.width < frameSize.width)
    videoBox.origin.x = (frameSize.width - size.width) / 2;
  else
    videoBox.origin.x = (size.width - frameSize.width) / 2;

  if (size.height < frameSize.height)
    videoBox.origin.y = (frameSize.height - size.height) / 2;
  else
    videoBox.origin.y = (size.height - frameSize.height) / 2;

  return videoBox;
}

- (void)dealloc {
  [self teardownAVCapture];
  [faceDetector release];
  [square release];
  [mainView release];
  [menWomen release];
  [super dealloc];
}

// use front/back camera
- (IBAction)switchCameras:(id)sender {
  AVCaptureDevicePosition desiredPosition;
  if (isUsingFrontFacingCamera)
    desiredPosition = AVCaptureDevicePositionBack;
  else
    desiredPosition = AVCaptureDevicePositionFront;

  for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
    if ([d position] == desiredPosition) {
      [[previewLayer session] beginConfiguration];
      AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:d error:nil];
      for (AVCaptureInput *oldInput in [[previewLayer session] inputs]) {
        [[previewLayer session] removeInput:oldInput];
      }
      [[previewLayer session] addInput:input];
      [[previewLayer session] commitConfiguration];
      break;
    }
  }
  isUsingFrontFacingCamera = !isUsingFrontFacingCamera;
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad {
  [super viewDidLoad];
  // Do any additional setup after loading the view, typically from a nib.
  [self setupAVCapture];
  NSDictionary *detectorOptions = [[NSDictionary alloc] initWithObjectsAndKeys:CIDetectorAccuracyLow, CIDetectorAccuracy, nil];
  faceDetector = [[CIDetector detectorOfType:CIDetectorTypeFace context:nil options:detectorOptions] retain];
  convnetClassifier = [[ConvnetClassifier alloc] init];
  wnid_men = [[NSBundle mainBundle] URLForResource:@"starface-men" withExtension:@"wnid"];
  wnid_women = [[NSBundle mainBundle] URLForResource:@"starface-women" withExtension:@"wnid"];
  artistsData = [[ArtistsData alloc] initWithWNID:wnid_men wnid_women:wnid_women];
  NSLog(@"initialized artists data...");

  textView.textColor = [UIColor whiteColor];
  [textView setFont:[UIFont fontWithName:@"Helvetica Neue" size:20.0f]];
  textView.TextAlignment = NSTextAlignmentCenter;
  men = false;
  [detectorOptions release];
}

- (void)viewDidUnload {
  [super viewDidUnload];
  // Release any retained subviews of the main view.
  // e.g. self.myOutlet = nil;
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  // Return YES for supported orientations
  return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
  if ([gestureRecognizer isKindOfClass:[UIPinchGestureRecognizer class]]) {
    beginGestureScale = effectiveScale;
  }
  return YES;
}

- (IBAction)changeGenderButtonPressed:(id)sender {
  // UIImageView *imgView = [[UIImageView alloc]initWithImage:[UIImage imageNamed:@"button women on.png"]];
  // [self->menWomen setBackgroundImage:imgView];

  men = !men;
  if (men) {
    [menWomen setBackgroundImage:[UIImage imageNamed:@"button men on.png"] forState:UIControlStateNormal];
  } else {
    [menWomen setBackgroundImage:[UIImage imageNamed:@"button women on.png"] forState:UIControlStateNormal];
  }
  NSLog(@"gender changed");
}

@end

//
//  ViewController.h
//  Starface
//
//  Created by Johan Mathe on 3/2/15.
//  Copyright (c) 2015 starface. All rights reserved.
//

#include "ConvnetClassifier.h"
#include "ArtistsData.h"

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@class CIDetector;

@interface ViewController : UIViewController<UIGestureRecognizerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate> {
  IBOutlet UIView *previewView;
  IBOutlet UITextView *textView;
  IBOutlet UISegmentedControl *camerasControl;
  AVCaptureVideoPreviewLayer *previewLayer;
  AVCaptureVideoDataOutput *videoDataOutput;
  BOOL detectFaces;
  dispatch_queue_t videoDataOutputQueue;
  AVCaptureStillImageOutput *stillImageOutput;
  UIView *flashView;
  UIImage *square;
  BOOL isUsingFrontFacingCamera;
  CIDetector *faceDetector;
  CGFloat beginGestureScale;
  CGFloat effectiveScale;
  ConvnetClassifier *convnetClassifier;
  ArtistsData *artistsData;
  NSURL *synsets;
  NSURL *wnid_men;
  NSURL *wnid_women;
  IBOutlet UIView *mainView;

  IBOutlet UIButton *menWomen;
  CFDictionaryRef attachmenstTaken;
  CGImageRef picTaken;
  bool men;
}

- (IBAction)changeGenderButtonPressed:(id)sender;
- (CGImageRef)CGImageRotatedByAngle:(CGImageRef)imgRef angle:(CGFloat)angle;
- (IBAction)takePicture:(id)sender;
- (IBAction)switchCameras:(id)sender;
- (IBAction)toggleFaceDetection:(id)sender;
- (IBAction)starfaceButtonClicked:(id)sender;
- (NSString *)messageFromConfidence:(float)confidence;

@end

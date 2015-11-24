//
//  PhotoViewController.m
//  Starface
//
//  Created by Johan Mathe on 3/7/15.
//  Copyright (c) 2015 starface. All rights reserved.
//

#import "PhotoViewController.h"
#import "ConvnetClassifier.h"

#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <AssertMacros.h>
#import <AssetsLibrary/AssetsLibrary.h>

@interface PhotoViewController ()

@end

@implementation PhotoViewController

@synthesize picTaken;
@synthesize attachmenstTaken;
@synthesize texttoshare;
@synthesize men;

-(NSString*) GetRandomTitle {
    int i = 3; //arc4random() % 6;
    switch (i)
    {
        case 0:
            return @"pro tip: you'll get better results if you smile.";
            break;
        case 1:
            return @"pro tip: good lighting is important.";
            break;
        case 2:
            return @"pro tip: Make sure you've selected the right gender on the top right.";
            break;
        case 3:
            return @"Running a \"deep learning\" algorithm...";
            break;
        case 4:
            return @"pro tip: you will get better results without glasses.";
            break;
        case 5:
            return @"pro tip: you will get better results if your head is straight.";
            break;
        default:
            return @"Integer out of range";
            break;
    }
    return nil;
}

- (NSString *)messageFromConfidence:(float)confidence {
  if (confidence < 0.2) {
    return @"You kind of look like %@. But from very far away...";
  } else if (confidence < 0.4) {
    return @"You look like %@. Has anyone told you before?";
  } else if (confidence < 0.6) {
    return @"You look a lot like %@. Are you related?";
  } else if (confidence < 0.98) {
    return @"Wow. You are %@'s true doppelgänger.";
  } else if (confidence >= 0.98) {
    return @"You don't fool me. I know this is %@. :)";
  } else {
    return @"Something went horribly wrong";
  }
}

- (NSString *)shareMessageFromConfidence:(float)confidence {
  if (confidence < 0.2) {
    return @"I kind of look like %@. But from very far away... Download the app Starface and find out who you look like! (http://ow.ly/Kwktw)";
  } else if (confidence < 0.4) {
    return @"I look like %@. Do you see the resemblance? Download the app Starface and find out who you look like! (http://ow.ly/Kwktw)";
  } else if (confidence < 0.6) {
    return @"I look a lot like %@. Do you see the resemblance? Download the app Starface and find out who you look like! (http://ow.ly/Kwktw)";
  } else if (confidence < 0.98) {
    return @"I am %@'s true doppelganger. Do you see the resemblance? Download the app Starface and find out who you look like! .";
  } else if (confidence >= 0.98) {
    return @"I took a picture of %@ with Starface;) Download the app Starface and find out who you look like! (http://ow.ly/Kwktw)";
  } else {
    return @"Something went horribly wrong";
  }
}

- (UIImage *)imageWithMainView {
  UIGraphicsBeginImageContext(mainView.bounds.size);
  [mainView.layer renderInContext:UIGraphicsGetCurrentContext()];

  UIImage *img = UIGraphicsGetImageFromCurrentImageContext();

  UIGraphicsEndImageContext();

  return img;
}

- (CGImageRef)applyFilter:(CGImageRef)image {
  CIImage *beginImage = [CIImage imageWithCGImage:image];
  CIContext *context = [CIContext contextWithOptions:nil];

  CIFilter *filter = [CIFilter filterWithName:@"CIPhotoEffectProcess" keysAndValues:kCIInputImageKey, beginImage, nil];
  CIImage *outputImage = [filter outputImage];

  filter = [CIFilter filterWithName:@"CIVignette" keysAndValues:kCIInputImageKey, outputImage, @"inputIntensity", [NSNumber numberWithFloat:1.0], nil];
  outputImage = [filter outputImage];

  return [context createCGImage:outputImage fromRect:[outputImage extent]];
  ;
}

- (BOOL)writeCGImageToCameraRoll:(CGImageRef)cgImage withMetadata:(NSDictionary *)metadata {
  CGImageRef rotated = [self CGImageRotatedByAngle:cgImage angle:-90.0];

  CGImageRef filtered = [self applyFilter:rotated];

  imagetoshare = [UIImage imageWithCGImage:filtered];
  [imageView initWithImage:imagetoshare];

  CGImageRelease(filtered);

  NSArray *classification_results = [convnetClassifier classify:rotated men:men];

  NSMutableString *text = [NSMutableString stringWithCapacity:1024];
  [text setString:@""];

  for (ClassificationResult *idresult in classification_results) {
    [text appendFormat:[self messageFromConfidence:[idresult confidence]], [self->artistsData artistName:[idresult uid] men:men]];
    self.texttoshare = [NSString stringWithFormat:[self shareMessageFromConfidence:[idresult confidence]]];
    UIImage *artistImage = [UIImage imageNamed:[NSString stringWithFormat:@"%@.jpg", [self->artistsData synset:[idresult uid] men:men]]];
    CGImageRef imageRef = [artistImage CGImage];
    imageRef = [self applyFilter:imageRef];
    [artistImageView initWithImage:[UIImage imageWithCGImage:imageRef]];
    break;
  }
  textView.text = text;
  textView.textColor = [UIColor whiteColor];
  [textView setFont:[UIFont fontWithName:@"Helvetica Neue" size:18.0f]];
  textView.TextAlignment = NSTextAlignmentCenter;
  [textView sizeToFit];

  return true;
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

- (void)viewDidLoad {
  [super viewDidLoad];
  self->texttoshare = [NSMutableString alloc];
  // Do any additional setup after loading the view.
  [indicator startAnimating];
  [indicator hidesWhenStopped];
  CGImageRef rotated = [self CGImageRotatedByAngle:[self picTaken] angle:-90.0];

  CGImageRef filtered = [self applyFilter:rotated];

  imagetoshare = [UIImage imageWithCGImage:filtered];
  [imageView initWithImage:imagetoshare];
    
    textView.text = [self GetRandomTitle];
    textView.textColor = [UIColor whiteColor];
    [textView setFont:[UIFont fontWithName:@"Helvetica Neue" size:18.0f]];
    textView.TextAlignment = NSTextAlignmentCenter;
    [textView sizeToFit];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  [self writeCGImageToCameraRoll:[self picTaken] withMetadata:(id)[self attachmenstTaken]];
  [indicator stopAnimating];
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  // Dispose of any resources that can be recreated.
}

#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little
// preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
  // Get the new view controller using [segue destinationViewController].
  // Pass the selected object to the new view controller.
}

+ (PhotoViewController *)createPhotoViewController:(ConvnetClassifier *)net artists:(ArtistsData *)artists attachments:(CFDictionaryRef)attachments pic:(CGImageRef)pic men:(bool)men {
  UIStoryboard *sb = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
  PhotoViewController *view = [sb instantiateViewControllerWithIdentifier:@"PhotoViewController"];
  view->attachmenstTaken = attachments;
  view->picTaken = pic;
  view->convnetClassifier = net;
  view->artistsData = artists;
  view->men = men;
  return view;
}

- (IBAction)shareButtonPressed:(id)sender {
  NSArray *activityItems = @[ texttoshare, [self imageWithMainView] ];
  UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:activityItems applicationActivities:nil];
  [self presentViewController:activityVC animated:TRUE completion:nil];
}

- (IBAction)popPhotoController:(id)sender {
  NSLog(@"pop photo pressed");
  [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)dealloc {
  [imageView release];
  [mainView release];
  [indicator release];
  [super dealloc];
}
@end

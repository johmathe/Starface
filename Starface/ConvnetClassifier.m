//
//  ConvnetClassifier.m
//  Starface
//
//  Created by Johan Mathe on 3/3/15.
//  Copyright (c) 2015 starface. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "ConvnetClassifier.h"
#import "ccv.h"

@implementation ClassificationResult

@synthesize uid;
@synthesize confidence;

- (id)init {
  self = [super init];
  if (self) {
    // Initialization code here.
  }

  return self;
}

+ (id)createResult:(int)uid andConfidence:(float)confidence {
  ClassificationResult *result = [[[self alloc] init] autorelease];
  result->uid = uid;
  result->confidence = confidence;
  return result;
}

@end

@implementation ConvnetClassifier {
  ccv_convnet_t *_convnet_men;
  ccv_convnet_t *_convnet_women;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    NSURL *imageNetMen = [[NSBundle mainBundle] URLForResource:@"starface-mobile-men" withExtension:@"sqlite3"];
    NSURL *imageNetWomen = [[NSBundle mainBundle] URLForResource:@"starface-mobile-women" withExtension:@"sqlite3"];

    _convnet_men = ccv_convnet_read(0, imageNetMen.fileSystemRepresentation);
    _convnet_women = ccv_convnet_read(0, imageNetWomen.fileSystemRepresentation);
    if (imageNetMen == nil) {
      NSLog(@"NILLL! for men");
    }
    if (imageNetWomen == nil) {
      NSLog(@"NILLL! for women");
    }
  }
  return self;
}

- (NSArray *)classify:(CGImageRef)image men:(bool)men {
  int width = (int)CGImageGetWidth(image);
  int height = (int)CGImageGetHeight(image);
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate(0, width, height, 8, width * 4, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedLast);
  CGColorSpaceRelease(colorSpace);
  CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
  uint8_t *data = (uint8_t *)CGBitmapContextGetData(context);
  ccv_dense_matrix_t *a = 0;
  ccv_read(data, &a, CCV_IO_RGBA_RAW | CCV_IO_RGB_COLOR, height, width, width * 4);
  CGContextRelease(context);
  ccv_dense_matrix_t *classiable = 0;
  ccv_array_t *ranks = 0;
  if (men) {
    ccv_convnet_input_formation(_convnet_men, a, &classiable);
    ccv_convnet_classify(_convnet_men, &classiable, 1, &ranks, 5, 1);

  } else {
    ccv_convnet_input_formation(_convnet_women, a, &classiable);
    ccv_convnet_classify(_convnet_women, &classiable, 1, &ranks, 5, 1);
  }
  ccv_matrix_free(classiable);
  // collect classification result
  NSMutableArray *classifications = [NSMutableArray array];
  int i;
  for (i = 0; i < ranks->rnum; i++) {
    ccv_classification_t *classification = (ccv_classification_t *)ccv_array_get(ranks, i);
    NSLog(@"%d", classification->id);
    [classifications addObject:[ClassificationResult createResult:classification->id andConfidence:classification->confidence]];
  }
  ccv_array_free(ranks);
  return [classifications copy];
}

- (void)dealloc {
  [super dealloc];
  ccv_convnet_free(_convnet_men);
  ccv_convnet_free(_convnet_women);
}

@end

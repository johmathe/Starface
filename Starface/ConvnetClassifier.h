//
//  ConvnetClassifier.h
//  Starface
//
//  Created by Johan Mathe on 3/3/15.
//  Copyright (c) 2015 starface. All rights reserved.
//

#ifndef Starface_ConvnetClassifier_h
#define Starface_ConvnetClassifier_h

#import <Foundation/Foundation.h>

#import <CoreGraphics/CoreGraphics.h>

@interface ClassificationResult : NSObject {
  int uid;
  double confidence;
}

+ (id)createResult:(int)uid andConfidence:(float)confidence;

@property(readonly) int uid;
@property(readonly) double confidence;

@end

@interface ConvnetClassifier : NSObject

- (NSArray *)classify:(CGImageRef)image men:(bool)men;

@end

#endif

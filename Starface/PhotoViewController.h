//
//  PhotoViewController.h
//  Starface
//
//  Created by Johan Mathe on 3/7/15.
//  Copyright (c) 2015 starface. All rights reserved.
//

#include "ConvnetClassifier.h"
#include "ArtistsData.h"

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface PhotoViewController : UIViewController {
  IBOutlet UITextView *textView;
  ConvnetClassifier *convnetClassifier;
  ArtistsData *artistsData;
  NSURL *synsets;
  NSURL *wnid;
  IBOutlet UIImageView *imageView;
  IBOutlet UIImageView *artistImageView;
  IBOutlet UIView *mainView;
  IBOutlet UIActivityIndicatorView *indicator;
  CFDictionaryRef attachmenstTaken;
  CGImageRef picTaken;
  UIImage *imagetoshare;
  NSString *texttoshare;
  bool men;
}

- (IBAction)shareButtonPressed:(id)sender;
- (CGImageRef)CGImageRotatedByAngle:(CGImageRef)imgRef angle:(CGFloat)angle;
- (IBAction)popPhotoController:(id)sender;
- (CGImageRef)applyFilter:(CGImageRef)image;
- (UIImage *)imageWithMainView;
- (NSString*) GetRandomTitle;

+ (PhotoViewController *)createPhotoViewController:(ConvnetClassifier *)net artists:(ArtistsData *)artists attachments:(CFDictionaryRef)attachments pic:(CGImageRef)pic men:(bool)men;

@property(readwrite) CFDictionaryRef attachmenstTaken;
@property(readwrite) CGImageRef picTaken;
@property(nonatomic, retain) NSString *texttoshare;
@property(readonly) bool men;

@end

//
//  ArtistsData.h
//  Starface
//
//  Created by Johan Mathe on 3/3/15.
//  Copyright (c) 2015 starface. All rights reserved.
//

#ifndef Starface_ArtistsData_h
#define Starface_ArtistsData_h

#import <Foundation/Foundation.h>

@interface ArtistsData : NSObject

- (instancetype)initWithWNID:(NSURL *)wnidurl_men wnid_women:(NSURL *)wnidurl_women;

- (NSString *)synset:(NSUInteger)cid men:(BOOL)men;
- (NSString *)artistName:(NSUInteger)cid men:(BOOL)men;
@end

#endif

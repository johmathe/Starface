//
//  ArtistsData.m
//  Starface
//
//  Created by Johan Mathe on 3/3/15.
//  Copyright (c) 2015 starface. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ArtistsData.h"

@interface ArtistsData ()
@end

@implementation ArtistsData {
  NSArray *_wnids_men;
  NSArray *_wnids_women;
}

- (instancetype)initWithWNID:(NSURL *)wnidurl_men wnid_women:(NSURL *)wnidurl_women {
  self = [super init];
  if (self) {
    NSString *wnidListMen = [NSString stringWithContentsOfURL:wnidurl_men encoding:NSUTF8StringEncoding error:nil];
    NSString *wnidListWomen = [NSString stringWithContentsOfURL:wnidurl_women encoding:NSUTF8StringEncoding error:nil];
    _wnids_men = [[wnidListMen componentsSeparatedByString:@"\n"] retain];
    _wnids_women = [[wnidListWomen componentsSeparatedByString:@"\n"] retain];
  }
  return self;
}

- (NSString *)synset:(NSUInteger)cid men:(BOOL)men {
  if (men) {
    return _wnids_men[cid];
  } else {
    return _wnids_women[cid];
  }
}

- (NSString *)artistName:(NSUInteger)cid men:(bool)men {
  NSString *clean_name;
  if (men) {
    clean_name = [_wnids_men[cid] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
  } else {
    clean_name = [_wnids_women[cid] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
  }
  return [clean_name capitalizedString];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
}

@end

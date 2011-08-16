//
//  HotKeyHandler.h
//  macistrano
//
//  Created by Alex Speller on 15/08/2011.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <ShortcutRecorder/ShortcutRecorder.h>

@interface HotKeyHandler : NSObject {
	IBOutlet NSObject *preferencesController;
}

- (void)shortcutRecorder:(SRRecorderControl *)aRecorder keyComboDidChange:(KeyCombo)newKeyCombo;

@end

//
//  HotKeyHandler.m
//  macistrano
//
//  Created by Alex Speller on 15/08/2011.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "HotKeyHandler.h"


@implementation HotKeyHandler

- (void)shortcutRecorder:(SRRecorderControl *)aRecorder keyComboDidChange:(KeyCombo)newKeyCombo
{
	[preferencesController change_quick_deploy_shortcut];
}

@end

//
//  SceneDelegate.m
//  ClaudeLegacy
//

#import "SceneDelegate.h"
#import "DebugConsole.h"

@implementation SceneDelegate

- (void)sceneDidBecomeActive:(UIScene *)scene {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
        [[DebugConsole shared] installStderrTap];
        [[DebugConsole shared] attachToWindowScene:(UIWindowScene *)scene];
    }
}

@end

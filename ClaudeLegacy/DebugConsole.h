#import <UIKit/UIKit.h>

@interface DebugConsole : NSObject

+ (instancetype)shared;

- (void)attachToWindowScene:(UIWindowScene *)scene;
- (void)installStderrTap;
- (void)append:(NSString *)line level:(NSString *)level;
- (void)setDumpHandler:(void (^)(void))handler;
- (NSString *)logFilePath;

@end

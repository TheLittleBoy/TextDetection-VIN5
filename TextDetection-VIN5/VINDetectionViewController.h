//
//  VINDetectionViewController.h
//  TextDetection-VIN5
//
//  Created by Mac on 2022/6/27.
//

#import <UIKit/UIKit.h>

@protocol VINDetectionViewControllerDelegate <NSObject>

/**
 识别成功之后，点击完成按钮的回调

 @param result VIN码
 */
- (void)recognitionComplete:(NSString *)result;

@end

@interface VINDetectionViewController : UIViewController

@property(nonatomic, weak) id<VINDetectionViewControllerDelegate> delegate;

@end

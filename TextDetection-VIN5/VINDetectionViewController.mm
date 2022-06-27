//
//  VINDetectionViewController.m
//  TextDetection-VIN5
//
//  Created by Mac on 2022/6/27.
//

#import <opencv2/opencv.hpp>
#import <opencv2/imgcodecs/ios.h>
#import <opencv2/videoio/cap_ios.h>
// clang-format on
#include "pipeline.h"
#include "timer.h"
#include <arm_neon.h>
#include <iostream>
#include <mutex>
#include "paddle_api.h"
#include "paddle_use_kernels.h"
#include "paddle_use_ops.h"
#include <string>
#import <sys/timeb.h>
#include <vector>

#import <AVFoundation/AVFoundation.h>
#import "VINDetectionViewController.h"


using namespace paddle::lite_api;
using namespace cv;

std::mutex mtx;
Pipeline *pipe_;
Timer tic;
long long count = 0;

@interface VINDetectionViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>
{
    UILabel *textLabel;
    AVCaptureDevice *device;
    NSString *recognizedText;
    BOOL isFocus;
    BOOL isInference;
}
@property (nonatomic, assign) CGFloat m_width; //扫描框宽度
@property (nonatomic, assign) CGFloat m_higth; //扫描框高度
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDeviceInput *videoInput;
@property (nonatomic, strong) AVCaptureVideoDataOutput *captureVideoDataOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

@property(nonatomic) std::string dict_path;
@property(nonatomic) std::string config_path;
@end

#define SCREEN_WIDTH ([[UIScreen mainScreen] bounds].size.width)
#define SCREEN_HEIGHT ([[UIScreen mainScreen] bounds].size.height)
#define m_scanViewY  150.0
#define m_scale [UIScreen mainScreen].scale

@implementation VINDetectionViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.title = @"扫一扫";
    self.view.backgroundColor = [UIColor whiteColor];

    //给个默认值
    self.m_width = (SCREEN_WIDTH - 40);
    self.m_higth = 80.0;
    recognizedText = @"";
    
    //模型初始化
    [self initModel];
    
    //初始化摄像头
    [self initAVCaptureSession];
}

- (void)initModel {
    
    NSString *path = [[NSBundle mainBundle] bundlePath];
    std::string paddle_dir = std::string([path UTF8String]);
    std::string det_model_file =
        paddle_dir + "/ch_ppocr_mobile_v2.0_det_slim_opt.nb";
    std::string rec_model_file =
        paddle_dir + "/ch_ppocr_mobile_v2.0_rec_slim_opt.nb";
    std::string cls_model_file =
        paddle_dir + "/ch_ppocr_mobile_v2.0_cls_slim_opt.nb";
    std::string img_path = paddle_dir + "/test2.jpg";
    self.dict_path = paddle_dir + "/ppocr_keys_v1.txt";
    self.config_path = paddle_dir + "/config.txt";
    
    pipe_ = new Pipeline(det_model_file, cls_model_file, rec_model_file,
                         "LITE_POWER_HIGH", 1, self.config_path, self.dict_path);
}

- (void)initAVCaptureSession{
    
    self.session = [[AVCaptureSession alloc] init];
    NSError *error;
    
    device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    self.videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:device error:&error];
    if (error) {
        NSLog(@"%@",error);
    }
    
    //输出流
    NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    NSNumber* value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
    NSDictionary* videoSettings = [NSDictionary
                                   dictionaryWithObject:value forKey:key];
    self.captureVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.captureVideoDataOutput setVideoSettings:videoSettings];
    
    dispatch_queue_t queue;
    queue = dispatch_queue_create("cameraQueue", NULL);
    [self.captureVideoDataOutput setSampleBufferDelegate:self queue:queue];
    
    if ([self.session canAddInput:self.videoInput]) {
        [self.session addInput:self.videoInput];
    }
    if ([self.session canAddOutput:self.captureVideoDataOutput]) {
        [self.session addOutput:self.captureVideoDataOutput];
    }
    
    AVCaptureConnection* connection = [self.captureVideoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    
    //输出照片铺满屏幕
    if ([self.session canSetSessionPreset:AVCaptureSessionPresetHigh]) {
        self.session.sessionPreset = AVCaptureSessionPresetHigh;
    }
    
    //初始化预览图层
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    if (orientation == UIInterfaceOrientationPortrait) {
        [[self.previewLayer connection] setVideoOrientation:AVCaptureVideoOrientationPortrait];
        
    }
    else if (orientation == UIInterfaceOrientationLandscapeLeft) {
        [[self.previewLayer connection] setVideoOrientation:AVCaptureVideoOrientationLandscapeLeft];
    }
    else if (orientation == UIInterfaceOrientationLandscapeRight) {
        [[self.previewLayer connection] setVideoOrientation:AVCaptureVideoOrientationLandscapeRight];
    }
    else {
        [[self.previewLayer connection] setVideoOrientation:AVCaptureVideoOrientationPortraitUpsideDown];
    }
    
    self.previewLayer.frame = CGRectMake(0,0, SCREEN_WIDTH,SCREEN_HEIGHT);
    
    [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    
    self.view.layer.masksToBounds = YES;
    [self.view.layer addSublayer:self.previewLayer];
    
    //扫描框
    [self initScanView];
    
    //扫描结果label
    textLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, (SCREEN_HEIGHT - 100)/2.0, SCREEN_WIDTH, 100)];
    textLabel.textAlignment = NSTextAlignmentCenter;
    textLabel.numberOfLines = 0;
    
    textLabel.font = [UIFont systemFontOfSize:19];
    
    textLabel.textColor = [UIColor colorWithRed:1.00 green:0.50 blue:0.00 alpha:1.00];
    [self.view addSubview:textLabel];
    
    //完成按钮
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.view addSubview:button];
    button.frame = CGRectMake((SCREEN_WIDTH - 100)/2.0, SCREEN_HEIGHT - 164, 100, 50);
    [button setTitle:@"完成" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(clickedFinishBtn:) forControlEvents:UIControlEventTouchUpInside];
    
    //对焦
    int flags =NSKeyValueObservingOptionNew;
    [device addObserver:self forKeyPath:@"adjustingFocus" options:flags context:nil];
}

- (void)initScanView
{
    // 中间空心洞的区域
    CGRect cutRect = CGRectMake((SCREEN_WIDTH - _m_width)/2.0,m_scanViewY, _m_width, _m_higth);
    
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:CGRectMake(0,0, SCREEN_WIDTH,SCREEN_HEIGHT)];
    // 挖空心洞 显示区域
    UIBezierPath *cutRectPath = [UIBezierPath bezierPathWithRect:cutRect];
    
    //将circlePath添加到path上
    [path appendPath:cutRectPath];
    path.usesEvenOddFillRule = YES;
    
    CAShapeLayer *fillLayer = [CAShapeLayer layer];
    fillLayer.path = path.CGPath;
    fillLayer.fillRule = kCAFillRuleEvenOdd;
    fillLayer.opacity = 0.6;//透明度
    fillLayer.backgroundColor = [UIColor blackColor].CGColor;
    [self.view.layer addSublayer:fillLayer];
    
    // 边界校准线
    CGFloat lineWidth = 2;
    CGFloat lineLength = 20;
    UIBezierPath *linePath = [UIBezierPath bezierPathWithRect:CGRectMake(cutRect.origin.x - lineWidth,
                                                                         cutRect.origin.y - lineWidth,
                                                                         lineLength,
                                                                         lineWidth)];
    //追加路径
    [linePath appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(cutRect.origin.x - lineWidth,
                                                                     cutRect.origin.y - lineWidth,
                                                                     lineWidth,
                                                                     lineLength)]];
    
    [linePath appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(cutRect.origin.x + cutRect.size.width - lineLength + lineWidth,
                                                                     cutRect.origin.y - lineWidth,
                                                                     lineLength,
                                                                     lineWidth)]];
    [linePath appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(cutRect.origin.x + cutRect.size.width ,
                                                                     cutRect.origin.y - lineWidth,
                                                                     lineWidth,
                                                                     lineLength)]];
    
    [linePath appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(cutRect.origin.x - lineWidth,
                                                                     cutRect.origin.y + cutRect.size.height - lineLength + lineWidth,
                                                                     lineWidth,
                                                                     lineLength)]];
    [linePath appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(cutRect.origin.x - lineWidth,
                                                                     cutRect.origin.y + cutRect.size.height,
                                                                     lineLength,
                                                                     lineWidth)]];
    
    [linePath appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(cutRect.origin.x + cutRect.size.width,
                                                                     cutRect.origin.y + cutRect.size.height - lineLength + lineWidth,
                                                                     lineWidth,
                                                                     lineLength)]];
    [linePath appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(cutRect.origin.x + cutRect.size.width - lineLength + lineWidth,
                                                                     cutRect.origin.y + cutRect.size.height,
                                                                     lineLength,
                                                                     lineWidth)]];
    
    CAShapeLayer *pathLayer = [CAShapeLayer layer];
    pathLayer.path = linePath.CGPath;// 从贝塞尔曲线获取到形状
    pathLayer.fillColor = [UIColor colorWithRed:0. green:0.655 blue:0.905 alpha:1.0].CGColor; // 闭环填充的颜色
    [self.view.layer addSublayer:pathLayer];
    
    UILabel *tipLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, m_scanViewY - 40, SCREEN_WIDTH, 25)];
    [self.view addSubview:tipLabel];
    tipLabel.text = @"请对准VIN码进行扫描";
    tipLabel.textAlignment = NSTextAlignmentCenter;
    tipLabel.textColor = [UIColor whiteColor];
}

-(void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
    if([keyPath isEqualToString:@"adjustingFocus"]){
        BOOL adjustingFocus =[[change objectForKey:NSKeyValueChangeNewKey] isEqualToNumber:[NSNumber numberWithInt:1]];
        isFocus = adjustingFocus;
        NSLog(@"Is adjusting focus? %@", adjustingFocus ?@"YES":@"NO");
    }
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    //
    if (!isFocus && !isInference) {
        isInference = YES;
        
        //得到照片
        UIImage *originImage = [self imageFromSamplePlanerPixelBuffer:sampleBuffer];
        
        cv::Mat srcimg;
        UIImageToMat(originImage,srcimg);
        
        cv::Mat outCopyImg;
        
        if (srcimg.channels() == 4) {
            cvtColor(srcimg, outCopyImg, COLOR_RGBA2BGR);
        }else
        {
            cvtColor(srcimg, outCopyImg, COLOR_RGB2BGR);
        }
        
        tic.start();

        std::vector<std::string> res_txt;
        std::vector<float> res_txt_score;
        cv::Mat img_vis =
          pipe_->Process(outCopyImg,res_txt,res_txt_score);

        tic.end();
        //print recognized text
        std::ostringstream result;
        result << "花费了" << tic.get_average_ms() << " ms\n";
        NSLog(@"%@",[NSString stringWithUTF8String:result.str().c_str()]);
        
        //
        for (int i = 0; i < res_txt.size(); i++) {

            NSString *elementText = [NSString stringWithUTF8String:res_txt[i].c_str()];
            NSLog(@"%@",elementText);

            float accuracy = res_txt_score[i];
            NSLog(@"%@",[NSString stringWithFormat:@"%f",accuracy]);

            //识别17位的VIN码
            if (elementText.length == 17 && accuracy>0.8) {
                //正则表达式，排除特殊字符
                NSString *regex = @"[ABCDEFGHJKLMNPRSTUVWXYZ1234567890]{17}";
                NSPredicate *test = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regex];
                //识别成功
                if ([test evaluateWithObject:elementText]) {

                    //连续两次识别结果一致，则输出最终结果
                    if ([self->recognizedText isEqualToString:elementText]) {

                        //播放音效
                        NSURL *url=[[NSBundle mainBundle]URLForResource:@"scanSuccess.wav" withExtension:nil];
                        SystemSoundID soundID=8787;
                        AudioServicesCreateSystemSoundID((__bridge CFURLRef)url, &soundID);
                        AudioServicesPlaySystemSound(soundID);

                        //在屏幕上输入结果
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self->textLabel.text = elementText;
                        });
                        
                        NSLog(@"%@",elementText);
                                            
                        //停止扫描
                        [self.session stopRunning];
                    
                    }else
                    {
                        //马上再识别一次，对比结果
                        self->recognizedText = elementText;
                        self->isInference = NO;
                    }
                    return;
                }
            }
        }

        //延迟50毫秒再继续识别下一次，降低CPU功耗，省电‼️
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            //继续识别
            self->isInference = NO;
        });
    }
}

- (void)viewWillAppear:(BOOL)animated{
    
    [super viewWillAppear:YES];
    
    if (self.session) {
        [self.session startRunning];
    }
}

- (void)viewDidDisappear:(BOOL)animated{
    
    [super viewDidDisappear:YES];
    
    if (self.session) {
        [self.session stopRunning];
    }
    
    [device removeObserver:self forKeyPath:@"adjustingFocus" context:nil];
}

/**
 完成按钮点击事件

 @param sender 按钮
 */
- (void)clickedFinishBtn:(UIButton *)sender {
    
    
    [self.navigationController popViewControllerAnimated:YES];
}

/**
 * 把 CMSampleBufferRef 转化成 UIImage 的方法，参考自：
 * https://stackoverflow.com/questions/19310437/convert-cmsamplebufferref-to-uiimage-with-yuv-color-space
 * note1 : SDK要求 colorSpace 为 CGColorSpaceCreateDeviceRGB
 * note2 : SDK需要 ARGB 格式的图片
 */
- (UIImage *) imageFromSamplePlanerPixelBuffer:(CMSampleBufferRef)sampleBuffer{
    @autoreleasepool {
        // Get a CMSampleBuffer's Core Video image buffer for the media data
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        // Lock the base address of the pixel buffer
        CVPixelBufferLockBaseAddress(imageBuffer, 0);
        
        // Get the number of bytes per row for the plane pixel buffer
        void *baseAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
        
        // Get the number of bytes per row for the plane pixel buffer
        size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer,0);
        // Get the pixel buffer width and height
        size_t width = CVPixelBufferGetWidth(imageBuffer);
        size_t height = CVPixelBufferGetHeight(imageBuffer);
        
        // Create a device-dependent RGB color space
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        
        // Create a bitmap graphics context with the sample buffer data
        CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                     bytesPerRow, colorSpace, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
        // Create a Quartz image from the pixel data in the bitmap graphics context
        CGImageRef quartzImage = CGBitmapContextCreateImage(context);
        // Unlock the pixel buffer
        CVPixelBufferUnlockBaseAddress(imageBuffer,0);
        
        // Free up the context and color space
        CGContextRelease(context);
        CGColorSpaceRelease(colorSpace);
        
        // Create an image object from the Quartz image
        UIImage *image = [UIImage imageWithCGImage:quartzImage];
        
        // Release the Quartz image
        CGImageRelease(quartzImage);
        return (image);
    }
}
/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end

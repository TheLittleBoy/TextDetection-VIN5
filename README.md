# TextDetection-VIN5

iOS使用飞桨OCR文字识别，实现离线扫描VIN码，免费，并且效果极佳，速度贼快。

飞桨官网：https://www.paddlepaddle.org.cn

官网OCR demo：https://ai.baidu.com/easyedge/app/openSource

官方 demo git：https://github.com/PaddlePaddle/Paddle-Lite-Demo

此项目需要自行下载较大的类库：

opencv2.framework 放在PaddleLite目录下，大小501M，下载地址：https://paddlelite-demo.bj.bcebos.com/libs/ios/opencv-4.5.5-ios-framework.tar.gz

libpaddle_api_light_bundled.a 放在PaddleLite/lib目录下，大小45M，下载地址：https://paddlelite-demo.bj.bcebos.com/libs/ios/paddle_lite_libs_v2_10_rc.tar.gz

请耐心下载！

效果图：

![](https://github.com/TheLittleBoy/TextDetection-VIN5/blob/main/1.jpg)

## 目录详解

1. `lib` : 存放编译好的预测库

**备注：**
  如需更新预测库，例如更新 iOS v8 预测库 ，则将新的预测库更新到 `ppocr_demo/lib` 目录

2. `assets` : 存放 OCR demo 的模型、测试图片、标签文件及 config 文件

**备注：**

 - `./assets/labels/ppocr_keys_v1.txt` 是中文字典文件，如果使用的 模型是英文数字或其他语言的模型，需要更换为对应语言的字典.
 - 其他语言的字典文件，可从 PaddleOCR 仓库下载：`https://github.com/PaddlePaddle/PaddleOCR/tree/release/2.3/ppocr/utils`

3. `source` :  存放预测代码
    - `cls_process.cc` :  方向分类器的推理全流程，包含预处理、预测和后处理三部分
    
    - `rec_process.cc` :  识别模型 CRNN 的推理全流程，包含预处理、预测和后处理三部分
    
    - `det_process.cc` :  检测模型 CRNN 的推理全流程，包含预处理、预测和后处理三部分
    
    - `det_post_process` :  检测模型 DB 的后处理文件
    
    - `pipeline.cc` :  OCR 文字识别 Demo 推理全流程代码
    
    - `utils.cc` :  Tensor 相关处理代码
    
    - `time.cc` :  计时代码

4. `models` :  存放模型文件
    - `ch_ppocr_mobile_v2.0_det_slim_opt.nb`           优化后的检测模型文件

    - `ch_ppocr_mobile_v2.0_rec_slim_opt.nb`          优化后的识别模型文件

    - `ch_ppocr_mobile_v2.0_cls_slim_opt.nb`           优化后的文字方向分类器模型文件

    - `ppocr_keys_v1.txt`                              中文字典文件

    - `libpaddle_light_api_shared.so`                  C++预测库文件

    - `config.txt` 包含了检测器、分类器的超参数，如下：

```shell
max_side_len  960          # 输入图像长宽大于960时，等比例缩放图像，使得图像最长边为960
det_db_thresh  0.3         # 用于过滤DB预测的二值化图像，设置为0.-0.3对结果影响不明显
det_db_box_thresh  0.5     # DB后处理过滤box的阈值，如果检测存在漏框情况，可酌情减小
det_db_unclip_ratio  1.6   # 表示文本框的紧致程度，越小则文本框更靠近文本
det_db_use_dilate 0        # 
det_use_polygon_score 1    # 
use_direction_classify  1  # 是否使用方向分类器，0表示不使用，1表示使用
```
## 原理

OCR 文字识别 Demo 由三个模型一起完成 OCR 文字识别功能，对输入图片先通过 `ch_ppocr_mobile_v2.0_det_slim_opt.nb` 模型做检测处理，然后通过 `ch_ppocr_mobile_v2.0_cls_slim_opt.nb` 模型做文字方向分类处理，最后通过 `ch_ppocr_mobile_v2.0_rec_slim_opt.nb` 模型完成文字识别处理。

1. `pipeline.cc` : OCR 文字识别 Demo 预测全流程代码
  该文件完成了三个模型串行推理的全流程控制处理，包含整个处理过程的调度处理。

  - `Pipeline::Pipeline(...)` 方法完成调用三个模型类构造函数，完成模型加载和线程数、绑核处理及 predictor 创建处理
  - `Pipeline::Process(...)` 方法用于完成这三个模型串行推理的全流程控制处理
  
2. `cls_process.cc` 方向分类器的预测文件
  该文件完成了方向分类器的预处理、预测和后处理过程

  - `ClsPredictor::ClsPredictor()`  方法用于完成模型加载和线程数、绑核处理及 predictor 创建处理
  - `ClsPredictor::Preprocess()` 方法用于模型的预处理
  - `ClsPredictor::Postprocess()` 方法用于模型的后处理

3. `rec_process.cc` 识别模型 CRNN 的预测文件
  该文件完成了识别模型 CRNN 的预处理、预测和后处理过程

  - `RecPredictor::RecPredictor()`  方法用于完成模型加载和线程数、绑核处理及 predictor 创建处理
  - `RecPredictor::Preprocess()` 方法用于模型的预处理
  - `RecPredictor::Postprocess()` 方法用于模型的后处理

4. `det_process.cc` 检测模型 DB 的预测文件
  该文件完成了检测模型 DB 的预处理、预测和后处理过程

  - `DetPredictor::DetPredictor()`  方法用于完成模型加载和线程数、绑核处理及 predictor 创建处理
  - `DetPredictor::Preprocess()` 方法用于模型的预处理
  - `DetPredictor::Postprocess()` 方法用于模型的后处理

5. `db_post_process` 检测模型 DB 的后处理函数，包含 clipper 库的调用
  该文件完成了检测模型 DB 的第三方库调用和其他后处理方法实现

  - `std::vector<std::vector<std::vector<int>>> BoxesFromBitmap(...)` 方法从 Bitmap 图中获取检测框
  - `std::vector<std::vector<std::vector<int>>> FilterTagDetRes(...)` 方法根据识别结果获取目标框位置
 
 

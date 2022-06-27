# TextDetection-VIN5

iOS使用飞桨OCR文字识别，实现离线扫描VIN码，免费，并且效果极佳，速度贼快。


|--ch_ppocr_mobile_v2.0_det_slim_opt.nb           优化后的检测模型文件
|--ch_ppocr_mobile_v2.0_rec_slim_opt.nb           优化后的识别模型文件
|--ch_ppocr_mobile_v2.0_cls_slim_opt.nb           优化后的文字方向分类器模型文件
|--ppocr_keys_v1.txt                中文字典文件
|--libpaddle_light_api_shared.so    C++预测库文件
|--config.txt                       超参数配置


config.txt 包含了检测器、分类器的超参数，如下：

max_side_len  960          # 输入图像长宽大于960时，等比例缩放图像，使得图像最长边为960
det_db_thresh  0.3         # 用于过滤DB预测的二值化图像，设置为0.-0.3对结果影响不明显
det_db_box_thresh  0.5     # DB后处理过滤box的阈值，如果检测存在漏框情况，可酌情减小
det_db_unclip_ratio  1.6   # 表示文本框的紧致程度，越小则文本框更靠近文本
det_db_use_dilate 0        # 
det_use_polygon_score 1    # 
use_direction_classify  1  # 是否使用方向分类器，0表示不使用，1表示使用

效果图：

![](https://github.com/TheLittleBoy/TextDetection-VIN5/blob/main/1.jpg)

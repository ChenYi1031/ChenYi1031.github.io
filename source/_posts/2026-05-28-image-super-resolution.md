---
title: 百炼平台图像超分实战：老照片修复与低清图放大技术解析
date: 2026-05-28 10:00:00
tags:
  - 图像处理
  - 超分辨率
  - 百炼平台
categories:
  - AI实践
---

## 前言

在实际项目中，我们经常遇到客户需要处理低清图片的需求，特别是老照片修复和图像放大场景。本文分享在阿里云百炼平台上集成图像超分能力的实战经验。

## 图像超分技术原理

### 什么是超分辨率？

超分辨率（Super Resolution）是指从低分辨率图像恢复出高分辨率图像的技术。

```
┌─────────────────────────────────────────────────────────┐
│                    图像超分流程                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────┐      ┌─────────────┐      ┌────────┐  │
│  │  低清图片   │ ───▶ │  超分模型   │ ───▶ │ 高清图 │  │
│  │  (LR)       │      │  (SR Model) │      │ (HR)   │  │
│  └─────────────┘      └─────────────┘      └────────┘  │
│                                                         │
│  256x256              2x/4x放大           1024x1024      │
│  模糊、噪点多         深度学习             清晰、细节丰富 │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 常用超分模型

| 模型 | 放大倍数 | 特点 | 适用场景 |
|------|---------|------|---------|
| ESRGAN | 4x | 生成效果好，细节丰富 | 老照片修复 |
| Real-ESRGAN | 4x | 真实感强，抗噪能力强 | 真实场景图片 |
| SwinIR | 4x | 效果最佳，计算量大 | 高质量需求 |
| BSRGAN | 4x | 去噪+超分联合 | 老旧照片 |

## 百炼平台集成方案

### 1. API调用方式

```python
import requests
import base64
from pathlib import Path

class ImageSuperResolution:
    """百炼平台图像超分客户端"""
    
    def __init__(self, api_key):
        self.api_key = api_key
        self.base_url = "https://bailian.aliyuncs.com/v1/image/super-resolution"
    
    def upscale(self, image_path, scale_factor=2, model="real-esrgan"):
        """
        图像超分辨率处理
        
        Args:
            image_path: 输入图片路径
            scale_factor: 放大倍数 (2/4)
            model: 模型选择 (real-esrgan/esrgan/swinir)
        """
        # 读取图片并编码
        with open(image_path, 'rb') as f:
            image_data = base64.b64encode(f.read()).decode('utf-8')
        
        # 调用API
        headers = {
            'Authorization': f'Bearer {self.api_key}',
            'Content-Type': 'application/json'
        }
        
        payload = {
            'image': image_data,
            'scale_factor': scale_factor,
            'model': model
        }
        
        response = requests.post(self.base_url, json=payload, headers=headers)
        
        if response.ok:
            result = response.json()
            return {
                'success': True,
                'image': base64.b64decode(result['image']),
                'original_size': result['original_size'],
                'output_size': result['output_size']
            }
        else:
            return {
                'success': False,
                'error': response.text
            }
    
    def batch_process(self, input_dir, output_dir, scale_factor=2):
        """批量处理图片"""
        input_path = Path(input_dir)
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
        
        results = []
        
        for img_file in input_path.glob('*.{jpg,jpeg,png,bmp}'):
            print(f"处理: {img_file.name}")
            
            result = self.upscale(str(img_file), scale_factor)
            
            if result['success']:
                output_file = output_path / f"{img_file.stem}_hr.png"
                with open(output_file, 'wb') as f:
                    f.write(result['image'])
                
                results.append({
                    'input': str(img_file),
                    'output': str(output_file),
                    'status': 'success',
                    'original_size': result['original_size'],
                    'output_size': result['output_size']
                })
            else:
                results.append({
                    'input': str(img_file),
                    'status': 'failed',
                    'error': result['error']
                })
        
        return results


# 使用示例
client = ImageSuperResolution(api_key="your_api_key")

# 单张处理
result = client.upscale("old_photo.jpg", scale_factor=4)
if result['success']:
    with open("old_photo_hr.png", 'wb') as f:
        f.write(result['image'])

# 批量处理
results = client.batch_process("input_photos/", "output_photos/", scale_factor=2)
```

### 2. 本地部署方案

```python
# 本地部署Real-ESRGAN
import cv2
import numpy as np
from basicsr.archs.rrdbnet_arch import RRDBNet
from realesrgan import RealESRGANer

class LocalSuperResolution:
    """本地超分辨率处理"""
    
    def __init__(self, model_path, scale=4):
        # 定义模型
        model = RRDBNet(
            num_in_ch=3,
            num_out_ch=3,
            num_feat=64,
            num_block=23,
            num_grow_ch=32,
            scale=scale
        )
        
        # 初始化放大器
        self.upsampler = RealESRGANer(
            scale=scale,
            model_path=model_path,
            model=model,
            tile=0,
            tile_pad=10,
            pre_pad=0,
            half=True  # 使用FP16加速
        )
    
    def enhance(self, input_path, output_path):
        """增强图片"""
        # 读取图片
        img = cv2.imread(input_path, cv2.IMREAD_UNCHANGED)
        
        # 超分辨率处理
        output, _ = self.upsampler.enhance(img, outscale=4)
        
        # 保存结果
        cv2.imwrite(output_path, output)
        
        return {
            'input_shape': img.shape,
            'output_shape': output.shape,
            'output_path': output_path
        }
    
    def restore_old_photo(self, input_path, output_path):
        """老照片修复"""
        # 读取图片
        img = cv2.imread(input_path, cv2.IMREAD_UNCHANGED)
        
        # 1. 去噪
        denoised = cv2.fastNlMeansDenoisingColored(
            img, None, 10, 10, 7, 21
        )
        
        # 2. 超分辨率
        enhanced, _ = self.upsampler.enhance(denoised, outscale=4)
        
        # 3. 颜色校正
        corrected = self._color_correction(enhanced)
        
        # 保存结果
        cv2.imwrite(output_path, corrected)
        
        return {
            'input_shape': img.shape,
            'output_shape': corrected.shape,
            'output_path': output_path
        }
    
    def _color_correction(self, img):
        """颜色校正"""
        # 转换到LAB颜色空间
        lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
        l, a, b = cv2.split(lab)
        
        # CLAHE增强亮度通道
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        l = clahe.apply(l)
        
        # 合并并转换回BGR
        lab = cv2.merge([l, a, b])
        corrected = cv2.cvtColor(lab, cv2.COLOR_LAB2BGR)
        
        return corrected


# 使用示例
local_sr = LocalSuperResolution(
    model_path="weights/RealESRGAN_x4plus.pth",
    scale=4
)

# 老照片修复
result = local_sr.restore_old_photo(
    "old_photo.jpg",
    "old_photo_restored.png"
)
print(f"修复完成: {result['output_shape']}")
```

## 实际应用案例

### 案例1：某档案馆老照片数字化

**项目背景**：
- 客户：某市档案馆
- 需求：将10万张历史照片数字化
- 挑战：照片年代久远，质量参差不齐

**解决方案**：

```python
# 档案馆照片处理流水线
class ArchivePhotoPipeline:
    """档案馆照片处理流水线"""
    
    def __init__(self):
        self.sr_client = ImageSuperResolution(api_key="your_key")
        self.local_sr = LocalSuperResolution("weights/RealESRGAN_x4plus.pth")
    
    def process_archive(self, archive_dir, output_dir):
        """处理档案照片"""
        results = {
            'total': 0,
            'success': 0,
            'failed': 0,
            'details': []
        }
        
        for photo_path in Path(archive_dir).glob('*.{jpg,jpeg,png}'):
            results['total'] += 1
            
            try:
                # 1. 图片质量评估
                quality = self._assess_quality(photo_path)
                
                # 2. 根据质量选择处理方式
                if quality['score'] < 0.5:
                    # 低质量：使用云端API
                    result = self.sr_client.upscale(
                        str(photo_path), 
                        scale_factor=4,
                        model="real-esrgan"
                    )
                else:
                    # 高质量：使用本地模型
                    result = self.local_sr.enhance(
                        str(photo_path),
                        str(output_dir / f"{photo_path.stem}_hr.png")
                    )
                
                results['success'] += 1
                results['details'].append({
                    'input': str(photo_path),
                    'quality_score': quality['score'],
                    'status': 'success'
                })
                
            except Exception as e:
                results['failed'] += 1
                results['details'].append({
                    'input': str(photo_path),
                    'error': str(e),
                    'status': 'failed'
                })
        
        return results
    
    def _assess_quality(self, image_path):
        """评估图片质量"""
        img = cv2.imread(str(image_path))
        
        # 计算清晰度（拉普拉斯算子）
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()
        
        # 计算噪点
        noise_level = self._estimate_noise(gray)
        
        # 综合评分
        score = min(1.0, laplacian_var / 1000) * 0.7 + \
                max(0, 1 - noise_level / 50) * 0.3
        
        return {
            'score': score,
            'sharpness': laplacian_var,
            'noise_level': noise_level
        }
    
    def _estimate_noise(self, gray_img):
        """估计图片噪声"""
        # 使用中值绝对差估计噪声
        M = np.median(gray_img)
        sigma = np.median(np.abs(gray_img - M)) / 0.6745
        return sigma


# 运行处理
pipeline = ArchivePhotoPipeline()
results = pipeline.process_archive("archive_photos/", "output/")
print(f"处理完成: 成功{results['success']}, 失败{results['failed']}")
```

### 案例2：某电商平台商品图优化

**项目背景**：
- 客户：某电商平台
- 需求：提升商品图清晰度
- 挑战：图片量大，需要实时处理

**解决方案**：

```python
# 电商图片优化服务
class EcommerceImageService:
    """电商图片优化服务"""
    
    def __init__(self):
        self.cache = {}  # 结果缓存
    
    def optimize_product_image(self, image_url, max_size=1920):
        """优化商品图片"""
        # 检查缓存
        cache_key = f"{image_url}_{max_size}"
        if cache_key in self.cache:
            return self.cache[cache_key]
        
        # 下载图片
        response = requests.get(image_url)
        img_array = np.frombuffer(response.content, np.uint8)
        img = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
        
        # 获取原始尺寸
        h, w = img.shape[:2]
        
        # 如果已经够清晰，直接返回
        if max(h, w) >= max_size:
            return {'image': img, 'optimized': False}
        
        # 计算放大倍数
        scale = min(max_size / max(h, w), 4)
        
        # 超分辨率处理
        sr = LocalSuperResolution("weights/RealESRGAN_x4plus.pth")
        enhanced, _ = sr.upsampler.enhance(img, outscale=scale)
        
        # 裁剪到目标尺寸
        h_new, w_new = enhanced.shape[:2]
        if max(h_new, w_new) > max_size:
            ratio = max_size / max(h_new, w_new)
            enhanced = cv2.resize(enhanced, 
                                 (int(w_new * ratio), int(h_new * ratio)))
        
        # 缓存结果
        self.cache[cache_key] = {
            'image': enhanced,
            'optimized': True,
            'original_size': (w, h),
            'output_size': (enhanced.shape[1], enhanced.shape[0])
        }
        
        return self.cache[cache_key]


# 使用示例
service = EcommerceImageService()
result = service.optimize_product_image(
    "https://example.com/product_image.jpg",
    max_size=1920
)
```

## 处理效果对比

| 场景 | 优化前 | 优化后 | 提升 |
|------|--------|--------|------|
| 分辨率 | 256x256 | 1024x1024 | 4倍放大 |
| 清晰度 | 模糊 | 清晰 | 显著提升 |
| 细节 | 丢失 | 丰富 | 大幅改善 |
| 处理时间 | - | 0.5s/张 | 实时可用 |

## 总结

通过在百炼平台集成图像超分能力，我们帮助客户解决了低清图细节丢失的问题：

1. **老照片修复**：成功将历史照片数字化，保留珍贵记忆
2. **电商优化**：提升商品图质量，提高用户购买意愿
3. **批量处理**：支持大规模图片处理，满足商业需求

图像超分技术在实际业务中有着广泛的应用前景，未来我们将继续探索更多应用场景。

---

*如有图像处理相关需求，欢迎交流探讨。*

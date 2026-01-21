import Foundation
import AppKit

/// 剪贴板监听服务
class ClipboardService {
    private var viewModel: ClipboardViewModel
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general
    
    init(viewModel: ClipboardViewModel) {
        self.viewModel = viewModel
        self.lastChangeCount = pasteboard.changeCount
    }
    
    /// 开始监听剪贴板变化
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    /// 停止监听
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    /// 检查剪贴板内容变化
    private func checkClipboard() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        
        // 检测图片
        if let imageData = getImageData() {
            let item = ClipboardItem(type: .image, imageData: imageData)
            DispatchQueue.main.async {
                self.viewModel.addItem(item)
            }
            return
        }
        
        // 检测文字
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            // 避免重复添加相同内容
            if let lastItem = viewModel.items.first,
               lastItem.type == .text,
               lastItem.textContent == text {
                return
            }
            
            let item = ClipboardItem(type: .text, textContent: text)
            DispatchQueue.main.async {
                self.viewModel.addItem(item)
            }
        }
    }
    
    /// 获取剪贴板中的图片数据
    private func getImageData() -> Data? {
        // 尝试获取 PNG 格式
        if let data = pasteboard.data(forType: .png) {
            return data
        }
        
        // 尝试获取 TIFF 格式并转换为 PNG
        if let data = pasteboard.data(forType: .tiff),
           let image = NSImage(data: data),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return pngData
        }
        
        return nil
    }
    
    /// 将内容复制到剪贴板
    func copyToClipboard(_ item: ClipboardItem) {
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let data = item.imageData {
                pasteboard.setData(data, forType: .png)
            }
        }
        
        // 更新 changeCount 避免重复检测
        lastChangeCount = pasteboard.changeCount
    }
}

import Foundation
import Carbon.HIToolbox

/// 全局快捷键服务
class HotkeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let callback: () -> Void
    
    // 快捷键 ID
    private let hotkeyID = EventHotKeyID(signature: OSType(0x414E5943), id: 1) // "ANYC"
    
    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
    
    /// 注册全局快捷键 Shift+Command+V
    func register() {
        // 定义事件类型
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        // 创建事件处理器
        let handlerBlock: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData else { return noErr }
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            
            DispatchQueue.main.async {
                print("快捷键被触发")
                service.callback()
            }
            
            return noErr
        }
        
        // 安装事件处理器
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            handlerBlock,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        
        guard status == noErr else {
            print("安装事件处理器失败: \(status)")
            return
        }
        
        // 注册热键: Shift(512) + Command(256) + V(9)
        // cmdKey = 1 << 8 (256), shiftKey = 1 << 9 (512)
        let modifiers = UInt32(shiftKey | cmdKey)
        let keyCode = UInt32(kVK_ANSI_V)
        
        var hotkeyID = self.hotkeyID
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        
        if registerStatus == noErr {
            print("全局快捷键注册成功: Cmd+Shift+V")
        } else {
            print("注册热键失败: \(registerStatus)")
        }
    }
    
    /// 注销快捷键
    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}

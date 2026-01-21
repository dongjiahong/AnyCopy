import Foundation
import ServiceManagement

/// 开机启动工具类
struct LaunchAtLogin {
    private static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.anycopy.app"
    
    /// 首次启动时配置（根据用户设置）
    static func configureIfNeeded() {
        let defaults = UserDefaults.standard
        let isEnabled = defaults.bool(forKey: "launchAtLogin")
        
        if isEnabled {
            setEnabled(true)
        }
    }
    
    /// 设置开机启动状态
    static func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("设置开机启动失败: \(error)")
            }
        } else {
            // macOS 13 以下版本使用旧 API
            SMLoginItemSetEnabled(bundleIdentifier as CFString, enabled)
        }
    }
    
    /// 检查当前开机启动状态
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // 旧版本无法直接检查，返回 UserDefaults 的值
            return UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
    }
}

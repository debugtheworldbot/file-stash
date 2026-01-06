//
//  HotKeyManager.swift
//  FileStash
//
//  管理全局快捷键
//

import Foundation
import AppKit
import Carbon.HIToolbox

/// 快捷键配置模型
struct HotKeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    
    var displayString: String {
        var parts: [String] = []
        
        if modifiers & UInt32(controlKey) != 0 {
            parts.append("⌃")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("⌥")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("⇧")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("⌘")
        }
        
        // 添加按键名称
        if let keyName = keyCodeToString(keyCode) {
            parts.append(keyName)
        }
        
        return parts.joined()
    }
    
    private func keyCodeToString(_ keyCode: UInt32) -> String? {
        let keyMap: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 49: "Space", 50: "`",
            // Function keys
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        return keyMap[keyCode]
    }
    
    // 默认快捷键: Control + Option + S
    static let defaultConfig = HotKeyConfig(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(controlKey | optionKey)
    )
}

/// 快捷键管理器
class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()
    
    @Published var currentConfig: HotKeyConfig
    @Published var isRecording: Bool = false
    @Published var hasAccessibilityPermission: Bool = false
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let saveKey = "HotKeyConfig"
    
    var onHotKeyPressed: (() -> Void)?
    
    private init() {
        // 加载保存的配置或使用默认配置
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let config = try? JSONDecoder().decode(HotKeyConfig.self, from: data) {
            currentConfig = config
        } else {
            currentConfig = HotKeyConfig.defaultConfig
        }
        
        checkAccessibilityPermission()
    }
    
    /// 检查辅助功能权限
    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }
    
    /// 请求辅助功能权限
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        // 延迟检查权限状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.checkAccessibilityPermission()
        }
    }
    
    /// 注册快捷键
    func registerHotKey() {
        // 先注销已有的快捷键
        unregisterHotKey()
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x46535448) // "FSTH"
        hotKeyID.id = 1
        
        // 安装事件处理器
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let handler: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            if let manager = HotKeyManager.shared.onHotKeyPressed {
                DispatchQueue.main.async {
                    manager()
                }
            }
            return noErr
        }
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandler
        )
        
        // 注册热键
        let status = RegisterEventHotKey(
            currentConfig.keyCode,
            currentConfig.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status != noErr {
            print("Failed to register hotkey: \(status)")
        }
    }
    
    /// 注销快捷键
    func unregisterHotKey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
    
    /// 更新快捷键配置
    func updateConfig(_ config: HotKeyConfig) {
        currentConfig = config
        saveConfig()
        registerHotKey()
    }
    
    /// 保存配置
    private func saveConfig() {
        if let data = try? JSONEncoder().encode(currentConfig) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }
    
    /// 从 NSEvent 转换修饰键
    static func modifiersFromNSEvent(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        return modifiers
    }
}

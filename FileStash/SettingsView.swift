//
//  SettingsView.swift
//  FileStash
//
//  设置界面 - 自定义快捷键
//

import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    @ObservedObject var hotKeyManager = HotKeyManager.shared
    @State private var isRecording = false
    @State private var tempKeyCode: UInt32?
    @State private var tempModifiers: UInt32 = 0
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            Text("快捷键设置")
                .font(.headline)
            
            // 权限状态
            permissionSection
            
            Divider()
            
            // 快捷键设置
            hotKeySection
            
            Spacer()
            
            // 按钮
            HStack {
                Button("恢复默认") {
                    hotKeyManager.updateConfig(HotKeyConfig.defaultConfig)
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 350, height: 340)
    }
    
    // MARK: - 权限状态
    private var permissionSection: some View {
        HStack {
            Image(systemName: hotKeyManager.hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(hotKeyManager.hasAccessibilityPermission ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("辅助功能权限")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(hotKeyManager.hasAccessibilityPermission ? "已授权" : "需要授权才能使用全局快捷键")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !hotKeyManager.hasAccessibilityPermission {
                Button("授权") {
                    hotKeyManager.requestAccessibilityPermission()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
    }
    
    // MARK: - 快捷键设置
    private var hotKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("打开暂存区快捷键")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                // 快捷键显示/录制区域
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isRecording ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    
                    if isRecording {
                        Text(recordingDisplayString)
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .foregroundColor(.accentColor)
                    } else {
                        Text(hotKeyManager.currentConfig.displayString)
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                    }
                }
                .frame(height: 40)
                
                Button(isRecording ? "取消" : "录制") {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }
                .buttonStyle(.bordered)
            }
            
            Text("点击「录制」后，按下你想要的快捷键组合")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var recordingDisplayString: String {
        if tempKeyCode == nil && tempModifiers == 0 {
            return "请按下快捷键..."
        }
        
        var parts: [String] = []
        if tempModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if tempModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if tempModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if tempModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        
        if let keyCode = tempKeyCode {
            let config = HotKeyConfig(keyCode: keyCode, modifiers: tempModifiers)
            if let lastChar = config.displayString.last {
                parts.append(String(lastChar))
            }
        }
        
        return parts.isEmpty ? "请按下快捷键..." : parts.joined()
    }
    
    private func startRecording() {
        isRecording = true
        tempKeyCode = nil
        tempModifiers = 0
        
        // 监听键盘事件
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            if isRecording {
                let modifiers = HotKeyManager.modifiersFromNSEvent(event.modifierFlags)
                
                // 需要至少一个修饰键
                if modifiers != 0 {
                    let newConfig = HotKeyConfig(keyCode: UInt32(event.keyCode), modifiers: modifiers)
                    hotKeyManager.updateConfig(newConfig)
                    stopRecording()
                }
                return nil // 消费事件
            }
            return event
        }
        
        // 监听修饰键变化
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [self] event in
            if isRecording {
                tempModifiers = HotKeyManager.modifiersFromNSEvent(event.modifierFlags)
            }
            return event
        }
    }
    
    private func stopRecording() {
        isRecording = false
        tempKeyCode = nil
        tempModifiers = 0
    }
}

// MARK: - Preview
#Preview {
    SettingsView()
}

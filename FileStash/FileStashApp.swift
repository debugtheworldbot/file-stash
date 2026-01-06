//
//  FileStashApp.swift
//  FileStash
//
//  文件暂存区 - macOS 应用
//  支持拖拽文件到屏幕左下角进行暂存
//

import SwiftUI
import Carbon.HIToolbox

@main
struct FileStashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // 使用 Settings 场景来避免显示主窗口
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var floatingWindow: NSWindow?
    var settingsWindow: NSWindow?
    var fileStashManager = FileStashManager.shared
    var hotKeyManager = HotKeyManager.shared
    var dragMonitor: Any?
    var globalClickMonitor: Any?
    var statusItem: NSStatusItem?
    
    // 热区配置（仅用于拖拽时触发）
    let dragThreshold: CGFloat = 200
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 首先请求辅助功能权限
        requestAccessibilityPermissionIfNeeded()
        
        setupFloatingWindow()
        setupMenuBar()
        setupHotKey()
        setupDragTracking()
        setupClickOutsideMonitor()
        
        // 隐藏 Dock 图标
        NSApp.setActivationPolicy(.accessory)
    }
    
    // MARK: - 请求辅助功能权限
    func requestAccessibilityPermissionIfNeeded() {
        if !AXIsProcessTrusted() {
            // 弹出系统权限请求对话框
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        
        // 持续检查权限状态
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                self?.hotKeyManager.checkAccessibilityPermission()
                self?.hotKeyManager.registerHotKey()
                timer.invalidate()
            }
        }
    }
    
    func setupFloatingWindow() {
        // 创建悬浮窗口
        let contentView = FloatingStashView()
        
        floatingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 450),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        guard let window = floatingWindow else { return }
        
        // 设置窗口属性
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating  // 悬浮在其他窗口之上
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]  // 在所有桌面显示
        window.isMovableByWindowBackground = false
        window.contentView = NSHostingView(rootView: contentView)
        window.alphaValue = 0  // 默认隐藏
        
        // 定位到屏幕左下角
        positionWindowAtBottomLeft()
        
        window.orderFront(nil)
    }
    
    func positionWindowAtBottomLeft() {
        guard let window = floatingWindow,
              let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        
        // 左下角位置，留一点边距
        let x = screenFrame.origin.x + 10
        let y = screenFrame.origin.y + 10
        
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    // MARK: - 菜单栏设置
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "tray.fill", accessibilityDescription: "File Stash")
        }
        
        updateMenuBarMenu()
    }
    
    func updateMenuBarMenu() {
        let menu = NSMenu()
        
        let shortcutString = hotKeyManager.currentConfig.displayString
        menu.addItem(NSMenuItem(title: "打开暂存区 (\(shortcutString))", action: #selector(toggleStash), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "快捷键设置...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc func toggleStash() {
        if floatingWindow?.alphaValue == 0 {
            showWindow()
            fileStashManager.isExpanded = true
        } else {
            hideWindow()
            fileStashManager.isExpanded = false
        }
    }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 280),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "FileStash 设置"
            settingsWindow?.contentView = NSHostingView(rootView: settingsView)
            settingsWindow?.center()
            settingsWindow?.isReleasedWhenClosed = false
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - 快捷键设置
    func setupHotKey() {
        // 设置快捷键回调
        hotKeyManager.onHotKeyPressed = { [weak self] in
            self?.toggleStash()
        }
        
        // 如果已有权限，立即注册快捷键
        if AXIsProcessTrusted() {
            hotKeyManager.registerHotKey()
        }
    }
    
    // MARK: - 点击窗口外部关闭
    func setupClickOutsideMonitor() {
        // 全局点击监听
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleClickOutside(event)
        }
    }
    
    func handleClickOutside(_ event: NSEvent) {
        guard let window = floatingWindow,
              window.alphaValue > 0 else { return }
        
        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = window.frame
        
        // 如果点击在窗口外部，则关闭窗口
        if !windowFrame.contains(mouseLocation) {
            DispatchQueue.main.async { [weak self] in
                self?.hideWindow()
                FileStashManager.shared.isExpanded = false
            }
        }
    }
    
    // MARK: - 拖拽监听（只有拖拽文件时才触发热区）
    func setupDragTracking() {
        // 监听拖拽事件 - 当用户开始拖拽文件时显示窗口
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleDrag(event)
        }
    }
    
    func handleDrag(_ event: NSEvent) {
        guard isDraggingFile(),
              let screen = NSScreen.main else { return }
        
        let mouseLocation = NSEvent.mouseLocation
        let screenFrame = screen.frame
        
        // 拖拽时检测是否靠近左下角
        let isNearHotCorner = mouseLocation.x < (screenFrame.origin.x + dragThreshold) &&
                              mouseLocation.y < (screenFrame.origin.y + dragThreshold)
        
        if isNearHotCorner {
            DispatchQueue.main.async { [weak self] in
                self?.showWindow()
                FileStashManager.shared.isExpanded = true
            }
        }
    }

    private func isDraggingFile() -> Bool {
        let dragPasteboard = NSPasteboard(name: .drag)
        return dragPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }
    
    func showWindow() {
        guard let window = floatingWindow else { return }
        
        if window.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().alphaValue = 1
            }
        }
    }
    
    func hideWindow() {
        guard let window = floatingWindow else { return }
        
        if window.alphaValue > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                window.animator().alphaValue = 0
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // 移除事件监听
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // 注销快捷键
        hotKeyManager.unregisterHotKey()
        
        // 应用退出时保存数据
        fileStashManager.saveFiles()
    }
}

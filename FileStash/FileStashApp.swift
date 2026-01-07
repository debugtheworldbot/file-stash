//
//  FileStashApp.swift
//  FileStash
//
//  文件暂存区 - macOS 应用
//  支持拖拽文件到屏幕左下角进行暂存
//

import SwiftUI

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
    var fileStashManager = FileStashManager.shared
    var dragMonitor: Any?
    var mouseDownMonitor: Any?
    var mouseUpMonitor: Any?
    var globalClickMonitor: Any?
    var statusItem: NSStatusItem?
    var mouseMoveMonitor: Any?
    var dragEndMonitor: Any?

    // 热区配置（仅用于拖拽时触发）
    let dragThreshold: CGFloat = 200

    // 拖拽检测相关
    var dragStartLocation: NSPoint?
    var dragStartTime: Date?
    var isDraggingFile: Bool = false
    let minDragDistance: CGFloat = 10  // 最小拖拽距离（像素）
    let minDragDuration: TimeInterval = 0.15  // 最小拖拽持续时间（秒）

    // 鼠标晃动检测相关（左下角）
    let shakeCornerThresholdX: CGFloat = 320  // 左下角热区宽度（覆盖窗口300+边距）
    let shakeCornerThresholdY: CGFloat = 470  // 左下角热区高度（覆盖窗口450+边距）
    var recentMousePositions: [(point: NSPoint, time: Date)] = []
    let shakeTimeWindow: TimeInterval = 1.0  // 检测时间窗口
    let shakeDirectionChanges: Int = 3  // 需要的方向变化次数
    let shakeMinDistance: CGFloat = 2  // 最小移动距离
    var lastShakeTriggerTime: Date?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupFloatingWindow()
        setupMenuBar()
        setupDragTracking()
        setupClickOutsideMonitor()
        setupMouseShakeDetection()
        setupDragEndMonitor()

        // 隐藏 Dock 图标
        NSApp.setActivationPolicy(.accessory)
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

        menu.addItem(NSMenuItem(title: "打开暂存区", action: #selector(toggleStash), keyEquivalent: ""))
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

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
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
        // 监听鼠标按下事件 - 记录起始位置和时间
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.dragStartLocation = NSEvent.mouseLocation
            self?.dragStartTime = Date()
            self?.isDraggingFile = false
        }
        
        // 监听鼠标释放事件 - 重置状态
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.dragStartLocation = nil
            self?.dragStartTime = nil
            self?.isDraggingFile = false
        }
        
        // 监听拖拽事件 - 判断是否是真正的文件拖拽
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleDrag(event)
        }
    }
    
    func handleDrag(_ event: NSEvent) {
        guard let screen = NSScreen.main,
              let startLocation = dragStartLocation,
              let startTime = dragStartTime else { return }
        
        let currentLocation = NSEvent.mouseLocation
        let screenFrame = screen.frame
        
        // 计算拖拽距离
        let dragDistance = sqrt(
            pow(currentLocation.x - startLocation.x, 2) +
            pow(currentLocation.y - startLocation.y, 2)
        )
        
        // 计算拖拽持续时间
        let dragDuration = Date().timeIntervalSince(startTime)
        
        // 只有当拖拽距离和持续时间都超过阈值时，才认为是真正的文件拖拽
        // 这样可以过滤掉简单的点击操作
        if dragDistance >= minDragDistance && dragDuration >= minDragDuration {
            isDraggingFile = true
        }
        
        // 只有确认是文件拖拽时，才检测热区
        guard isDraggingFile else { return }
        
        // 拖拽时检测是否靠近左下角
        let isNearHotCorner = currentLocation.x < (screenFrame.origin.x + dragThreshold) &&
                              currentLocation.y < (screenFrame.origin.y + dragThreshold)
        
        if isNearHotCorner {
            DispatchQueue.main.async { [weak self] in
                self?.showWindow()
                FileStashManager.shared.isExpanded = true
            }
        }
    }
    
    // MARK: - 鼠标晃动检测（左下角）
    func setupMouseShakeDetection() {
        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMove(event)
        }
    }

    func handleMouseMove(_ event: NSEvent) {
        guard let screen = NSScreen.main else { return }

        let currentLocation = NSEvent.mouseLocation
        let screenFrame = screen.frame
        let now = Date()

        // 检查是否在左下角区域（覆盖整个窗口范围）
        let isInBottomLeftCorner = currentLocation.x < (screenFrame.origin.x + shakeCornerThresholdX) &&
                                   currentLocation.y < (screenFrame.origin.y + shakeCornerThresholdY)

        guard isInBottomLeftCorner else {
            recentMousePositions.removeAll()
            return
        }

        // 记录鼠标位置
        recentMousePositions.append((point: currentLocation, time: now))

        // 移除超出时间窗口的记录
        recentMousePositions.removeAll { now.timeIntervalSince($0.time) > shakeTimeWindow }

        // 检测晃动
        if detectShake() {
            // 防止连续触发
            if let lastTrigger = lastShakeTriggerTime, now.timeIntervalSince(lastTrigger) < 1.0 {
                return
            }

            lastShakeTriggerTime = now
            recentMousePositions.removeAll()

            DispatchQueue.main.async { [weak self] in
                self?.showWindow()
                FileStashManager.shared.isExpanded = true
            }
        }
    }

    func detectShake() -> Bool {
        guard recentMousePositions.count >= 4 else { return false }

        var directionChanges = 0
        var lastDeltaX: CGFloat = 0
        var lastDeltaY: CGFloat = 0

        for i in 1..<recentMousePositions.count {
            let prev = recentMousePositions[i - 1].point
            let curr = recentMousePositions[i].point
            let deltaX = curr.x - prev.x
            let deltaY = curr.y - prev.y
            let distance = sqrt(deltaX * deltaX + deltaY * deltaY)

            // 忽略太小的移动
            if distance >= shakeMinDistance {
                // 使用点积检测方向反转（点积为负表示方向相反）
                if lastDeltaX != 0 || lastDeltaY != 0 {
                    let dotProduct = deltaX * lastDeltaX + deltaY * lastDeltaY
                    if dotProduct < 0 {
                        directionChanges += 1
                    }
                }
                lastDeltaX = deltaX
                lastDeltaY = deltaY
            }
        }

        return directionChanges >= shakeDirectionChanges
    }

    // MARK: - 拖拽结束检测（用于从暂存区拖出文件后删除）
    func setupDragEndMonitor() {
        // 使用定时器检测拖拽结束，因为拖放操作期间全局鼠标事件可能不会触发
        dragEndMonitor = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkDragCompletion()
        } as AnyObject
    }

    func checkDragCompletion() {
        // 检查是否有正在拖拽的文件
        guard let draggedFile = fileStashManager.draggedFile else { return }

        // 检查鼠标按键是否已释放（0 表示没有按键按下）
        let pressedButtons = NSEvent.pressedMouseButtons
        guard pressedButtons == 0 else { return }

        // 鼠标已释放，清除拖拽状态
        fileStashManager.draggedFile = nil

        // 检查鼠标释放位置是否在窗口外
        guard let window = floatingWindow else { return }

        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = window.frame

        // 如果鼠标在窗口外部，说明文件被拖出到其他地方
        // 只有未置顶的文件才会被删除，置顶的文件保留在暂存区
        if !windowFrame.contains(mouseLocation) && !draggedFile.isPinned {
            DispatchQueue.main.async { [weak self] in
                self?.fileStashManager.removeFile(draggedFile)
            }
        }
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
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = mouseMoveMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let timer = dragEndMonitor as? Timer {
            timer.invalidate()
        }

        // 应用退出时保存数据
        fileStashManager.saveFiles()
    }
}

//
//  FloatingStashView.swift
//  FileStash
//
//  悬浮在屏幕左下角的暂存区视图
//

import SwiftUI
import UniformTypeIdentifiers

struct FloatingStashView: View {
    @ObservedObject var manager = FileStashManager.shared
    @State private var isHovering = false
    @State private var isDraggingOver = false
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 展开后的文件列表
            if manager.isExpanded || isDraggingOver {
                expandedView
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
            }
            
            // 收起状态的触发区域（始终存在用于接收拖放）
            collapsedTrigger
        }
        .frame(width: 300, height: 450, alignment: .bottomLeading)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: manager.isExpanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isDraggingOver)
    }
    
    // MARK: - 收起状态的触发区域
    private var collapsedTrigger: some View {
        ZStack {
            // 不透明背景 - 展开或拖拽时显示
            if isDraggingOver || manager.isExpanded {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
            }

            // 彩色背景层 - 展开或拖拽时显示
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    isDraggingOver
                    ? Color.accentColor.opacity(0.3)
                    : (manager.isExpanded ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .frame(width: 64, height: 64)

            // 背景圆环 - 展开时显示，增强辨识度
            if manager.isExpanded {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2)
                    .frame(width: 64, height: 64)
            }

            // 图标 - 拖拽或展开时显示
            if isDraggingOver || manager.isExpanded {
                VStack(spacing: 5) {
                    Image(systemName: isDraggingOver ? "arrow.down.doc.fill" : "tray.fill")
                        .font(.system(size: manager.isExpanded ? 28 : 24, weight: .semibold))
                        .foregroundColor(isDraggingOver ? .accentColor : (manager.isExpanded ? .accentColor : .secondary))
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)

                    if !manager.stashedFiles.isEmpty {
                        Text("\(manager.stashedFiles.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor)
                                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                            )
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(width: 64, height: 64)
        .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
            handleDrop(providers: providers)
            return true
        }
    }
    
    // MARK: - 展开后的视图
    private var expandedView: some View {
        VStack(spacing: 0) {
            // 标题栏
            headerView
            
            Divider()
            
            // 文件列表
            if manager.stashedFiles.isEmpty {
                emptyStateView
            } else {
                fileListView
            }
        }
        .frame(width: 280, height: 380)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.bottom, 70)
        .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
            handleDrop(providers: providers)
            return true
        }
    }
    
    // MARK: - 标题栏
    private var headerView: some View {
        HStack {
            Image(systemName: "tray.full.fill")
                .foregroundColor(.accentColor)
            
            Text("文件暂存区")
                .font(.headline)
            
            Spacer()
            
            Text("\(manager.stashedFiles.count) 个文件")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !manager.stashedFiles.isEmpty {
                Button(action: {
                    withAnimation {
                        manager.clearAll()
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("清空所有")
            }
            
            // 关闭按钮
            Button(action: {
                withAnimation {
                    manager.isExpanded = false
                    // 通知 AppDelegate 隐藏窗口
                    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                        appDelegate.hideWindow()
                    }
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭 (⌃⌥S)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("拖拽文件到这里")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("支持文件和文件夹")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
            
            Text("快捷键: ⌃⌥S")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 文件列表视图
    private var fileListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(manager.stashedFiles) { file in
                    FileRowView(file: file)
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                }
            }
            .padding(12)
        }
    }
    
    // MARK: - 处理拖放
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }

                DispatchQueue.main.async {
                    // 检查是否是从暂存区拖出又拖回来的文件
                    if let draggedFile = manager.draggedFile,
                       draggedFile.originalPath == url.path {
                        // 是自己拖出的文件，不重复添加
                        manager.draggedFile = nil
                        return
                    }

                    _ = manager.addFile(from: url)
                    // 清除拖拽状态
                    manager.draggedFile = nil
                }
            }
        }
        return true
    }
}

// MARK: - 文件行视图
struct FileRowView: View {
    let file: StashedFile
    @ObservedObject var manager = FileStashManager.shared
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 文件图标/预览和置顶标识
            ZStack(alignment: .topTrailing) {
                // 显示图片预览或文件图标
                Group {
                    if let preview = manager.imagePreview(for: file) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 32, height: 32)

                            Image(nsImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    } else {
                        Image(nsImage: manager.icon(for: file))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                    }
                }

                // 置顶标识
                if file.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 14, height: 14)
                        )
                        .offset(x: 4, y: -4)
                }
            }

            // 文件信息
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(file.formattedSize)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if file.isDirectory {
                        Label("文件夹", systemImage: "folder")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // 操作按钮
            if isHovering {
                HStack(spacing: 8) {
                    // 置顶按钮
                    Button(action: {
                        withAnimation {
                            manager.togglePin(file)
                        }
                    }) {
                        Image(systemName: file.isPinned ? "pin.fill" : "pin")
                            .font(.caption)
                            .foregroundColor(file.isPinned ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(file.isPinned ? "取消置顶" : "置顶")

                    // 在 Finder 中显示
                    Button(action: {
                        manager.revealInFinder(file)
                    }) {
                        Image(systemName: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("在 Finder 中显示")

                    // 删除按钮
                    Button(action: {
                        withAnimation {
                            manager.removeFile(file)
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("从暂存区移除")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.gray.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onDrag {
            // 记录正在拖拽的文件
            FileStashManager.shared.draggedFile = file
            // 支持从暂存区拖出文件
            return NSItemProvider(object: file.url as NSURL)
        }
        .onTapGesture(count: 2) {
            // 双击打开文件
            manager.openFile(file)
        }
        .contextMenu {
            Button(file.isPinned ? "取消置顶" : "置顶") {
                withAnimation {
                    manager.togglePin(file)
                }
            }

            Divider()

            Button("打开") {
                manager.openFile(file)
            }

            Button("在 Finder 中显示") {
                manager.revealInFinder(file)
            }

            Divider()

            Button("从暂存区移除", role: .destructive) {
                withAnimation {
                    manager.removeFile(file)
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    FloatingStashView()
        .frame(width: 300, height: 450)
}

//
//  FileStashManager.swift
//  FileStash
//
//  管理暂存文件的核心类
//

import Foundation
import AppKit
import UniformTypeIdentifiers

/// 暂存文件模型
struct StashedFile: Identifiable, Codable, Equatable {
    let id: UUID
    let originalPath: String
    let fileName: String
    let fileExtension: String
    let isDirectory: Bool
    var fileSize: Int64
    let dateAdded: Date
    /// 标记文件大小是否还在计算中
    var isSizeCalculating: Bool = false
    /// 是否置顶
    var isPinned: Bool = false

    var displayName: String {
        if fileExtension.isEmpty {
            return fileName
        }
        return "\(fileName).\(fileExtension)"
    }

    var url: URL {
        URL(fileURLWithPath: originalPath)
    }

    var formattedSize: String {
        if isSizeCalculating {
            return "计算中..."
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    /// 是否为图片文件
    var isImageFile: Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif", "svg"]
        return imageExtensions.contains(fileExtension.lowercased())
    }

    // Codable 需要排除 isSizeCalculating
    enum CodingKeys: String, CodingKey {
        case id, originalPath, fileName, fileExtension, isDirectory, fileSize, dateAdded, isPinned
    }
}

/// 文件暂存管理器
class FileStashManager: ObservableObject {
    static let shared = FileStashManager()

    @Published var stashedFiles: [StashedFile] = []
    @Published var isExpanded: Bool = false

    /// 当前正在拖拽的文件（用于拖出后删除）
    var draggedFile: StashedFile?

    private let saveKey = "StashedFiles"

    /// 图标缓存，避免重复获取
    private var iconCache: [String: NSImage] = [:]
    /// 图片预览缓存
    private var previewCache: [String: NSImage] = [:]
    /// 后台队列用于计算文件夹大小
    private let sizeCalculationQueue = DispatchQueue(label: "com.filestash.sizeCalculation", qos: .utility)
    /// 后台队列用于生成图片预览
    private let previewGenerationQueue = DispatchQueue(label: "com.filestash.previewGeneration", qos: .userInitiated)

    private init() {
        loadFiles()
    }

    /// 获取文件图标（带缓存）
    func icon(for file: StashedFile) -> NSImage {
        if let cached = iconCache[file.originalPath] {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: file.originalPath)
        iconCache[file.originalPath] = icon
        return icon
    }

    /// 获取图片预览（只返回缓存，不阻塞）
    func imagePreview(for file: StashedFile) -> NSImage? {
        // 只为图片文件返回预览
        guard file.isImageFile else { return nil }

        // 只返回缓存，不生成
        return previewCache[file.originalPath]
    }

    /// 异步生成图片预览
    private func generateImagePreview(for file: StashedFile) {
        // 只为图片文件生成预览
        guard file.isImageFile else { return }

        // 如果已有缓存，跳过
        if previewCache[file.originalPath] != nil {
            return
        }

        let path = file.originalPath
        previewGenerationQueue.async { [weak self] in
            guard let self = self else { return }

            // 加载图片
            guard let image = NSImage(contentsOfFile: path) else {
                return
            }

            // 生成缩略图（32x32，完整显示不裁切）
            let targetSize = NSSize(width: 32, height: 32)
            let thumbnail = NSImage(size: targetSize)
            thumbnail.lockFocus()

            let imageRect = NSRect(origin: .zero, size: image.size)

            // 计算适配比例（保持宽高比，完整显示）
            let imageAspect = image.size.width / image.size.height

            var drawRect = NSRect.zero
            if imageAspect > 1 {
                // 图片更宽，以宽度为准
                drawRect.size.width = targetSize.width
                drawRect.size.height = targetSize.width / imageAspect
                drawRect.origin.x = 0
                drawRect.origin.y = (targetSize.height - drawRect.size.height) / 2
            } else {
                // 图片更高或正方形，以高度为准
                drawRect.size.height = targetSize.height
                drawRect.size.width = targetSize.height * imageAspect
                drawRect.origin.x = (targetSize.width - drawRect.size.width) / 2
                drawRect.origin.y = 0
            }

            image.draw(in: drawRect, from: imageRect, operation: .sourceOver, fraction: 1.0)
            thumbnail.unlockFocus()

            // 缓存并触发 UI 更新
            DispatchQueue.main.async {
                self.previewCache[path] = thumbnail
                // 触发 SwiftUI 更新
                self.objectWillChange.send()
            }
        }
    }
    
    /// 添加文件到暂存区
    func addFile(from url: URL) -> Bool {
        // 检查文件是否已存在
        if stashedFiles.contains(where: { $0.originalPath == url.path }) {
            return false
        }

        // 检查文件是否存在
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }

        let fileId = UUID()

        // 普通文件：直接获取大小；文件夹：先显示，后台计算
        if isDirectory.boolValue {
            let file = StashedFile(
                id: fileId,
                originalPath: url.path,
                fileName: url.deletingPathExtension().lastPathComponent,
                fileExtension: url.pathExtension,
                isDirectory: true,
                fileSize: 0,
                dateAdded: Date(),
                isSizeCalculating: true
            )
            stashedFiles.append(file)
            sortFiles()
            saveFiles()

            // 后台计算文件夹大小
            sizeCalculationQueue.async { [weak self] in
                let size = self?.calculateDirectorySize(url: url) ?? 0
                DispatchQueue.main.async {
                    guard let self = self,
                          let index = self.stashedFiles.firstIndex(where: { $0.id == fileId }) else { return }
                    self.stashedFiles[index].fileSize = size
                    self.stashedFiles[index].isSizeCalculating = false
                    self.saveFiles()
                }
            }
        } else {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let file = StashedFile(
                id: fileId,
                originalPath: url.path,
                fileName: url.deletingPathExtension().lastPathComponent,
                fileExtension: url.pathExtension,
                isDirectory: false,
                fileSize: fileSize,
                dateAdded: Date()
            )
            stashedFiles.append(file)
            sortFiles()
            saveFiles()

            // 如果是图片文件，异步生成预览
            generateImagePreview(for: file)
        }

        return true
    }
    
    /// 从暂存区移除文件
    func removeFile(_ file: StashedFile) {
        iconCache.removeValue(forKey: file.originalPath)
        previewCache.removeValue(forKey: file.originalPath)
        stashedFiles.removeAll { $0.id == file.id }
        saveFiles()
    }

    /// 移除所有文件
    func clearAll() {
        iconCache.removeAll()
        previewCache.removeAll()
        stashedFiles.removeAll()
        saveFiles()
    }

    /// 置顶/取消置顶文件
    func togglePin(_ file: StashedFile) {
        guard let index = stashedFiles.firstIndex(where: { $0.id == file.id }) else { return }
        stashedFiles[index].isPinned.toggle()
        sortFiles()
        saveFiles()
    }

    /// 排序文件列表：置顶的文件在最前面，其余按添加时间排序
    private func sortFiles() {
        stashedFiles.sort { file1, file2 in
            if file1.isPinned != file2.isPinned {
                return file1.isPinned
            }
            return file1.dateAdded > file2.dateAdded
        }
    }
    
    /// 在 Finder 中显示文件
    func revealInFinder(_ file: StashedFile) {
        let fileURL = URL(fileURLWithPath: file.originalPath)

        // 检查文件是否存在
        if FileManager.default.fileExists(atPath: file.originalPath) {
            // 使用 activateFileViewerSelecting 方法，更可靠
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            // 文件不存在，尝试打开父文件夹
            let parentURL = fileURL.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parentURL.path) {
                NSWorkspace.shared.open(parentURL)
            }
        }
    }
    
    /// 打开文件
    func openFile(_ file: StashedFile) {
        NSWorkspace.shared.open(file.url)
    }
    
    /// 保存文件列表到 UserDefaults
    func saveFiles() {
        if let encoded = try? JSONEncoder().encode(stashedFiles) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    /// 从 UserDefaults 加载文件列表
    func loadFiles() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([StashedFile].self, from: data) {
            // 过滤掉已不存在的文件
            stashedFiles = decoded.filter { FileManager.default.fileExists(atPath: $0.originalPath) }
            // 排序：置顶的文件在最前面
            sortFiles()

            // 异步生成图片预览
            for file in stashedFiles where file.isImageFile {
                generateImagePreview(for: file)
            }
        }
    }
    
    /// 计算文件夹大小
    private func calculateDirectorySize(url: URL) -> Int64 {
        var size: Int64 = 0
        let fileManager = FileManager.default
        
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    size += Int64(fileSize)
                }
            }
        }
        
        return size
    }
}

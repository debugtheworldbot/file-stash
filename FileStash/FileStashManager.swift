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

    // Codable 需要排除 isSizeCalculating
    enum CodingKeys: String, CodingKey {
        case id, originalPath, fileName, fileExtension, isDirectory, fileSize, dateAdded
    }
}

/// 文件暂存管理器
class FileStashManager: ObservableObject {
    static let shared = FileStashManager()

    @Published var stashedFiles: [StashedFile] = []
    @Published var isExpanded: Bool = false

    private let saveKey = "StashedFiles"

    /// 图标缓存，避免重复获取
    private var iconCache: [String: NSImage] = [:]
    /// 后台队列用于计算文件夹大小
    private let sizeCalculationQueue = DispatchQueue(label: "com.filestash.sizeCalculation", qos: .utility)

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
            stashedFiles.insert(file, at: 0)
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
            stashedFiles.insert(file, at: 0)
            saveFiles()
        }

        return true
    }
    
    /// 从暂存区移除文件
    func removeFile(_ file: StashedFile) {
        iconCache.removeValue(forKey: file.originalPath)
        stashedFiles.removeAll { $0.id == file.id }
        saveFiles()
    }

    /// 移除所有文件
    func clearAll() {
        iconCache.removeAll()
        stashedFiles.removeAll()
        saveFiles()
    }
    
    /// 在 Finder 中显示文件
    func revealInFinder(_ file: StashedFile) {
        NSWorkspace.shared.selectFile(file.originalPath, inFileViewerRootedAtPath: "")
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

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
    let fileSize: Int64
    let dateAdded: Date
    
    var displayName: String {
        if fileExtension.isEmpty {
            return fileName
        }
        return "\(fileName).\(fileExtension)"
    }
    
    var url: URL {
        URL(fileURLWithPath: originalPath)
    }
    
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: originalPath)
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

/// 文件暂存管理器
class FileStashManager: ObservableObject {
    static let shared = FileStashManager()
    
    @Published var stashedFiles: [StashedFile] = []
    @Published var isExpanded: Bool = false
    
    private let saveKey = "StashedFiles"
    
    private init() {
        loadFiles()
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
        
        // 获取文件大小
        let fileSize: Int64
        if isDirectory.boolValue {
            fileSize = calculateDirectorySize(url: url)
        } else {
            fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        
        let file = StashedFile(
            id: UUID(),
            originalPath: url.path,
            fileName: url.deletingPathExtension().lastPathComponent,
            fileExtension: url.pathExtension,
            isDirectory: isDirectory.boolValue,
            fileSize: fileSize,
            dateAdded: Date()
        )
        
        stashedFiles.insert(file, at: 0)
        saveFiles()
        return true
    }
    
    /// 从暂存区移除文件
    func removeFile(_ file: StashedFile) {
        stashedFiles.removeAll { $0.id == file.id }
        saveFiles()
    }
    
    /// 移除所有文件
    func clearAll() {
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

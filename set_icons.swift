#!/usr/bin/env swift

import Foundation
import AppKit

// 创建一个串行队列用于日志输出，避免并发时日志混乱
let logQueue = DispatchQueue(label: "com.bookmarks.logging")

func log(_ message: String) {
    logQueue.sync {
        print(message)
    }
}

func extractURLFromWebloc(filePath: String) -> String? {
    guard let data = FileManager.default.contents(atPath: filePath) else {
        log("❌ 无法读取文件: \(filePath)")
        return nil
    }
    
    do {
        if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let urlString = plist["URL"] as? String {
            return urlString
        }
    } catch {
        log("❌ 解析plist文件失败: \(error.localizedDescription)")
    }
    
    return nil
}

func extractDomainName(from urlString: String) -> String? {
    guard let url = URL(string: urlString),
          let host = url.host else {
        return nil
    }
    
    var domain = host.lowercased()
    
    // 如果是www开头，去掉www前缀
    if domain.hasPrefix("www.") {
        domain = String(domain.dropFirst(4))
    }
    
    return domain
}

// 创建一个串行队列用于图标设置操作
// 注意：NSWorkspace 和 NSImage 不是线程安全的，必须串行执行
let iconQueue = DispatchQueue(label: "com.bookmarks.icon", qos: .userInitiated)

func setFileIcon(filePath: String, iconPath: String) -> Bool {
    // 检查文件是否存在
    guard FileManager.default.fileExists(atPath: filePath),
          FileManager.default.fileExists(atPath: iconPath) else {
        log("❌ 文件不存在: \(filePath) 或 \(iconPath)")
        return false
    }
    
    var success = false
    
    // 在串行队列中执行图标设置，避免并发问题
    iconQueue.sync {
        // 创建图标
        guard let icon = NSImage(contentsOfFile: iconPath) else {
            log("❌ 无法加载图标文件: \(iconPath)")
            return
        }
        
        // 设置文件图标
        success = NSWorkspace.shared.setIcon(icon, forFile: filePath)
        if success {
            log("✅ 成功为 \(URL(fileURLWithPath: filePath).lastPathComponent) 设置图标")
        } else {
            log("❌ 设置图标失败")
        }
    }
    
    return success
}

func processWeblocFile(filePath: String, relativePath: String, iconsDir: String) -> Bool {
    // 从.webloc文件中提取URL
    guard let urlString = extractURLFromWebloc(filePath: filePath) else {
        log("⚠️  无法从 \(relativePath) 中提取URL")
        log("")
        return false
    }
    
    // 提取域名
    guard let domainName = extractDomainName(from: urlString) else {
        log("⚠️  无法从URL中提取域名: \(relativePath) -> \(urlString)")
        log("")
        return false
    }
    
    log("🌐 域名: \(domainName), \(relativePath) -> \(urlString)")
    
    // 查找对应的图标文件
    var iconPath: String?
    
    // 优先查找 .icns 文件
    let icnsPath = "\(iconsDir)/\(domainName).icns"
    if FileManager.default.fileExists(atPath: icnsPath) {
        iconPath = icnsPath
    } else {
        // 查找 .png 文件
        let pngPath = "\(iconsDir)/\(domainName).png"
        if FileManager.default.fileExists(atPath: pngPath) {
            iconPath = pngPath
        }
    }
    
    if let iconPath = iconPath {
        if setFileIcon(filePath: filePath, iconPath: iconPath) {
            return true
        }
    } else {
        log("⚠️  未找到域名 \(domainName) 对应的图标文件 (\(domainName).icns 或 \(domainName).png)")
    }
    log("")
    return false
}

func processDirectory(path: String, iconsDir: String, basePath: String) -> (success: Int, total: Int) {
    var successCount = 0
    var totalCount = 0
    let lock = NSLock()
    
    do {
        let items = try FileManager.default.contentsOfDirectory(atPath: path)
        
        // 使用 DispatchGroup 并行处理所有项目
        let dispatchGroup = DispatchGroup()
        let concurrentQueue = DispatchQueue(label: "com.bookmarks.processing", attributes: .concurrent)
        
        for item in items {
            dispatchGroup.enter()
            concurrentQueue.async {
                defer { dispatchGroup.leave() }
                let itemPath = "\(path)/\(item)"
                var isDirectory: ObjCBool = false
                
                if FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        // 如果是目录，递归处理
                        //let relativePath = String(itemPath.dropFirst(basePath.count + 1))
                        //log("📂 处理文件夹: \(relativePath)")
                        let result = processDirectory(path: itemPath, iconsDir: iconsDir, basePath: basePath)
                        
                        lock.lock()
                        successCount += result.success
                        totalCount += result.total
                        lock.unlock()
                    } else if item.hasSuffix(".webloc") {
                        // 如果是.webloc文件，处理它
                        let relativePath = String(itemPath.dropFirst(basePath.count + 1))
                        let success = processWeblocFile(filePath: itemPath, relativePath: relativePath, iconsDir: iconsDir)
                        
                        lock.lock()
                        totalCount += 1
                        if success {
                            successCount += 1
                        }
                        lock.unlock()
                    }
                }
            }
        }
        
        // 等待所有任务完成
        dispatchGroup.wait()
    } catch {
        log("❌ 读取目录失败: \(path) - \(error.localizedDescription)")
    }
    return (success: successCount, total: totalCount)
}

func main() {
    // 获取脚本所在目录
    let scriptPath = CommandLine.arguments[0]
    let scriptURL = URL(fileURLWithPath: scriptPath)
    let projectDir = scriptURL.deletingLastPathComponent().path
    let bookmarksDir = "\(projectDir)/bookmarks"
    let iconsDir = "\(projectDir)/icons"
    
    log("📁 项目目录: \(projectDir)")
    log("📁 Bookmarks目录: \(bookmarksDir)")
    log("📁 Icons目录: \(iconsDir)")
    
    // 检查目录是否存在
    guard FileManager.default.fileExists(atPath: bookmarksDir) else {
        log("❌ bookmarks 目录不存在: \(bookmarksDir)")
        exit(1)
    }
    
    guard FileManager.default.fileExists(atPath: iconsDir) else {
        log("❌ icons 目录不存在: \(iconsDir)")
        exit(1)
    }
    
    log("\n🚀 开始并行递归设置 webloc 文件图标...\n")
    
    let result = processDirectory(path: bookmarksDir, iconsDir: iconsDir, basePath: bookmarksDir)
    
    log("🎉 完成! 成功设置 \(result.success)/\(result.total) 个文件的图标")
}

// 运行主函数
main()

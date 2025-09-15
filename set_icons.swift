#!/usr/bin/env swift

import Foundation
import AppKit

func extractURLFromWebloc(filePath: String) -> String? {
    guard let data = FileManager.default.contents(atPath: filePath) else {
        print("❌ 无法读取文件: \(filePath)")
        return nil
    }
    
    do {
        if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let urlString = plist["URL"] as? String {
            return urlString
        }
    } catch {
        print("❌ 解析plist文件失败: \(error.localizedDescription)")
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

func setFileIcon(filePath: String, iconPath: String) -> Bool {
    // 检查文件是否存在
    guard FileManager.default.fileExists(atPath: filePath),
          FileManager.default.fileExists(atPath: iconPath) else {
        print("❌ 文件不存在: \(filePath) 或 \(iconPath)")
        return false
    }
    
    // 创建图标
    guard let icon = NSImage(contentsOfFile: iconPath) else {
        print("❌ 无法加载图标文件: \(iconPath)")
        return false
    }
    
    // 设置文件图标
    let success = NSWorkspace.shared.setIcon(icon, forFile: filePath)
    if success {
        print("✅ 成功为 \(URL(fileURLWithPath: filePath).lastPathComponent) 设置图标")
        return true
    } else {
        print("❌ 设置图标失败")
        return false
    }
}

func processWeblocFile(filePath: String, relativePath: String, iconsDir: String) -> Bool {
    // 从.webloc文件中提取URL
    guard let urlString = extractURLFromWebloc(filePath: filePath) else {
        print("⚠️  无法从 \(relativePath) 中提取URL")
        print("")
        return false
    }
    
    print("🐝 \(relativePath) -> \(urlString)")
    
    // 提取域名
    guard let domainName = extractDomainName(from: urlString) else {
        print("⚠️  无法从URL中提取域名: \(urlString)")
        print("")
        return false
    }
    
    print("🌐 域名: \(domainName)")
    
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
        print("🔧 使用图标: \(URL(fileURLWithPath: iconPath).lastPathComponent)")
        if setFileIcon(filePath: filePath, iconPath: iconPath) {
            print("")
            return true
        }
    } else {
        print("⚠️  未找到域名 \(domainName) 对应的图标文件 (\(domainName).icns 或 \(domainName).png)")
    }
    print("")
    return false
}

func processDirectory(path: String, iconsDir: String, basePath: String) -> (success: Int, total: Int) {
    var successCount = 0
    var totalCount = 0
    
    do {
        let items = try FileManager.default.contentsOfDirectory(atPath: path)
        
        for item in items {
            let itemPath = "\(path)/\(item)"
            var isDirectory: ObjCBool = false
            
            if FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // 如果是目录，递归处理
                    let relativePath = String(itemPath.dropFirst(basePath.count + 1))
                    print("📂 处理文件夹: \(relativePath)")
                    let result = processDirectory(path: itemPath, iconsDir: iconsDir, basePath: basePath)
                    successCount += result.success
                    totalCount += result.total
                } else if item.hasSuffix(".webloc") {
                    // 如果是.webloc文件，处理它
                    totalCount += 1
                    let relativePath = String(itemPath.dropFirst(basePath.count + 1))
                    if processWeblocFile(filePath: itemPath, relativePath: relativePath, iconsDir: iconsDir) {
                        successCount += 1
                    }
                }
            }
        }
    } catch {
        print("❌ 读取目录失败: \(path) - \(error.localizedDescription)")
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
    
    print("📁 项目目录: \(projectDir)")
    print("📁 Bookmarks目录: \(bookmarksDir)")
    print("📁 Icons目录: \(iconsDir)")
    
    // 检查目录是否存在
    guard FileManager.default.fileExists(atPath: bookmarksDir) else {
        print("❌ bookmarks 目录不存在: \(bookmarksDir)")
        exit(1)
    }
    
    guard FileManager.default.fileExists(atPath: iconsDir) else {
        print("❌ icons 目录不存在: \(iconsDir)")
        exit(1)
    }
    
    print("\n🚀 开始递归设置 webloc 文件图标...\n")
    
    let result = processDirectory(path: bookmarksDir, iconsDir: iconsDir, basePath: bookmarksDir)
    
    print("🎉 完成! 成功设置 \(result.success)/\(result.total) 个文件的图标")
}

// 运行主函数
main()

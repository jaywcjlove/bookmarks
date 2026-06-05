#!/usr/bin/env swift

import Foundation
import AppKit

enum Command: String {
    case setIcons = "--set-icons"
    case generateHTML = "--generate-html"
    case publishGHPages = "--publish-gh-pages"
    case includeGitHubLink = "--include-github-link"
    case help = "--help"
}

struct Bookmark {
    let title: String
    let url: String
    let iconFileName: String?
}

final class BookmarkFolder {
    let name: String
    var folders: [BookmarkFolder] = []
    var bookmarks: [Bookmark] = []

    init(name: String) {
        self.name = name
    }
}

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

func htmlEscaped(_ value: String) -> String {
    var result = value
    result = result.replacingOccurrences(of: "&", with: "&amp;")
    result = result.replacingOccurrences(of: "<", with: "&lt;")
    result = result.replacingOccurrences(of: ">", with: "&gt;")
    result = result.replacingOccurrences(of: "\"", with: "&quot;")
    result = result.replacingOccurrences(of: "'", with: "&#39;")
    return result
}

func sortedDirectoryItems(at path: String) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: path)
        .filter { !$0.hasPrefix(".") && $0 != "Icon\r" && $0 != "menuist.ini" }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

func webIconFileName(for domain: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_")
    return domain.unicodeScalars.map { scalar in
        allowed.contains(scalar) ? String(scalar) : "-"
    }.joined() + ".png"
}

func sourceIconPath(for urlString: String, iconsDir: String) -> String? {
    guard let domain = extractDomainName(from: urlString) else {
        return nil
    }

    let icnsPath = "\(iconsDir)/\(domain).icns"
    if FileManager.default.fileExists(atPath: icnsPath) {
        return icnsPath
    }

    let pngPath = "\(iconsDir)/\(domain).png"
    if FileManager.default.fileExists(atPath: pngPath) {
        return pngPath
    }

    return nil
}

func writeWebIcon(sourcePath: String, domain: String, outputIconsDir: String) -> String? {
    let outputName = webIconFileName(for: domain)
    let outputPath = "\(outputIconsDir)/\(outputName)"
    let sourceURL = URL(fileURLWithPath: sourcePath)

    do {
        try FileManager.default.createDirectory(atPath: outputIconsDir, withIntermediateDirectories: true)

        if sourceURL.pathExtension.lowercased() == "png" {
            if FileManager.default.fileExists(atPath: outputPath) {
                try FileManager.default.removeItem(atPath: outputPath)
            }
            try FileManager.default.copyItem(atPath: sourcePath, toPath: outputPath)
            return outputName
        }
    } catch {
        log("⚠️  复制网页图标失败: \(sourcePath) - \(error.localizedDescription)")
        return nil
    }

    let result = runCommand("/usr/bin/sips", [
        "-s", "format", "png",
        "--resampleWidth", "128",
        sourcePath,
        "--out", outputPath
    ], currentDirectory: URL(fileURLWithPath: sourcePath).deletingLastPathComponent().path)

    if result.status != 0 {
        log("⚠️  转换网页图标失败: \(sourcePath)\n\(result.output)")
        return nil
    }

    return outputName
}

func loadBookmarkFolder(path: String, name: String, iconsDir: String, outputIconsDir: String) -> BookmarkFolder {
    let folder = BookmarkFolder(name: name)

    do {
        for item in try sortedDirectoryItems(at: path) {
            let itemPath = "\(path)/\(item)"
            var isDirectory: ObjCBool = false

            guard FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                folder.folders.append(loadBookmarkFolder(path: itemPath, name: item, iconsDir: iconsDir, outputIconsDir: outputIconsDir))
            } else if item.hasSuffix(".webloc"), let url = extractURLFromWebloc(filePath: itemPath) {
                let title = URL(fileURLWithPath: item).deletingPathExtension().lastPathComponent
                let domain = extractDomainName(from: url)
                let sourceIcon = sourceIconPath(for: url, iconsDir: iconsDir)
                let iconFileName: String?
                if let domain, let sourceIcon {
                    iconFileName = writeWebIcon(sourcePath: sourceIcon, domain: domain, outputIconsDir: outputIconsDir)
                } else {
                    iconFileName = nil
                }
                folder.bookmarks.append(Bookmark(title: title, url: url, iconFileName: iconFileName))
            }
        }
    } catch {
        log("❌ 读取目录失败: \(path) - \(error.localizedDescription)")
    }

    return folder
}

func renderBookmarkCards(_ bookmarks: [Bookmark]) -> String {
    bookmarks.map { bookmark in
        let domain = extractDomainName(from: bookmark.url) ?? bookmark.url
        let letter = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "#"
        let iconMarkup: String

        if let iconFileName = bookmark.iconFileName {
            iconMarkup = """
              <span class="bookmark-icon has-image is-loading"><img src="icons/\(htmlEscaped(iconFileName))" alt="" loading="lazy" onload="this.parentElement.classList.add('is-loaded')" onerror="this.parentElement.classList.add('is-missing')"></span>
            """
        } else {
            iconMarkup = """
              <span class="bookmark-icon">\(htmlEscaped(letter.uppercased()))</span>
            """
        }

        return """
        <a class="bookmark-card" href="\(htmlEscaped(bookmark.url))" target="_blank" rel="noopener noreferrer" data-title="\(htmlEscaped(bookmark.title.lowercased()))" data-url="\(htmlEscaped(bookmark.url.lowercased()))">
        \(iconMarkup)
          <span class="bookmark-content">
            <span class="bookmark-title">\(htmlEscaped(bookmark.title))</span>
            <span class="bookmark-url">\(htmlEscaped(domain))</span>
          </span>
        </a>
        """
    }.joined(separator: "\n")
}

func renderFolder(_ folder: BookmarkFolder, level: Int = 0) -> String {
    let headingTag = min(level + 2, 6)
    var sections: [String] = []

    if !folder.bookmarks.isEmpty {
        sections.append("""
        <section class="bookmark-section">
          <h\(headingTag)>\(htmlEscaped(folder.name))</h\(headingTag)>
          <div class="bookmark-grid">
        \(renderBookmarkCards(folder.bookmarks))
          </div>
        </section>
        """)
    }

    for child in folder.folders {
        sections.append(renderFolder(child, level: level + 1))
    }

    return sections.joined(separator: "\n")
}

func countBookmarks(in folder: BookmarkFolder) -> Int {
    folder.bookmarks.count + folder.folders.reduce(0) { $0 + countBookmarks(in: $1) }
}

func normalizedGitHubURL(from remoteURL: String) -> String? {
    let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    var url = trimmed
    if url.hasPrefix("git@github.com:") {
        url = "https://github.com/" + String(url.dropFirst("git@github.com:".count))
    }

    if url.hasSuffix(".git") {
        url = String(url.dropLast(4))
    }

    guard url.hasPrefix("https://github.com/") else {
        return nil
    }

    return url
}

func currentGitHubURL(projectDir: String) -> String? {
    let result = runCommand("/usr/bin/git", ["remote", "get-url", "origin"], currentDirectory: projectDir)
    guard result.status == 0 else {
        return nil
    }

    return normalizedGitHubURL(from: result.output)
}

func renderGitHubLink(_ githubURL: String?) -> String {
    guard let githubURL else {
        return ""
    }

    return """
          <a class="github-link" href="\(htmlEscaped(githubURL))" target="_blank" rel="noopener noreferrer" aria-label="Open GitHub repository">
            <svg aria-hidden="true" viewBox="0 0 16 16" width="18" height="18">
              <path fill="currentColor" d="M8 0C3.58 0 0 3.67 0 8.2c0 3.63 2.29 6.7 5.47 7.79.4.08.55-.18.55-.4 0-.2-.01-.86-.01-1.56-2.01.38-2.53-.5-2.69-.96-.09-.24-.48-.96-.82-1.15-.28-.15-.68-.52-.01-.53.63-.01 1.08.59 1.23.84.72 1.24 1.87.89 2.33.68.07-.53.28-.89.51-1.1-1.78-.21-3.64-.91-3.64-4.03 0-.89.31-1.62.82-2.19-.08-.21-.36-1.04.08-2.16 0 0 .67-.22 2.2.84A7.4 7.4 0 0 1 8 3.99c.68 0 1.36.09 2 .28 1.52-1.06 2.19-.84 2.19-.84.44 1.12.16 1.95.08 2.16.51.57.82 1.3.82 2.19 0 3.13-1.87 3.82-3.65 4.03.29.26.54.76.54 1.53 0 1.1-.01 1.99-.01 2.26 0 .22.15.48.55.4A8.1 8.1 0 0 0 16 8.2C16 3.67 12.42 0 8 0Z"/>
            </svg>
            <span>GitHub</span>
          </a>
    """
}

func renderStaticHTML(root: BookmarkFolder, githubURL: String?) -> String {
    let total = countBookmarks(in: root)
    let generatedAt = ISO8601DateFormatter().string(from: Date())
    let pageTitle = "Bookmarks"
    let pageDescription = "A curated bookmark navigation page generated from organized .webloc files."
    let pageKeywords = "bookmarks,navigation,website directory,webloc,static site,GitHub Pages"

    return """
    <!doctype html>
    <html lang="zh-CN">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta name="description" content="\(htmlEscaped(pageDescription))">
      <meta name="keywords" content="\(htmlEscaped(pageKeywords))">
      <meta property="og:title" content="\(htmlEscaped(pageTitle))">
      <meta property="og:description" content="\(htmlEscaped(pageDescription))">
      <meta property="og:type" content="website">
      <meta name="twitter:card" content="summary">
      <meta name="twitter:title" content="\(htmlEscaped(pageTitle))">
      <meta name="twitter:description" content="\(htmlEscaped(pageDescription))">
      <title>\(htmlEscaped(pageTitle))</title>
      <style>
        :root {
          color-scheme: light dark;
          --bg: #f7f7f4;
          --text: #202124;
          --muted: #6b6f76;
          --line: #ddded8;
          --panel: #ffffff;
          --accent: #0f766e;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --bg: #171717;
            --text: #f2f2f0;
            --muted: #ffffff57;
            --line: #333633;
            --panel: #20211f;
            --accent: #2dd4bf;
          }
        }
        * { box-sizing: border-box; }
        body {
          margin: 0;
          background: var(--bg);
          color: var(--text);
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          line-height: 1.5;
          font-size: 14px;
        }
        main {
          width: min(1160px, calc(100% - 32px));
          margin: 0 auto;
          padding: 40px 0 56px;
          padding-bottom: 11rem;
        }
        header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 24px;
          border-bottom: 1px solid var(--line);
        }
        footer {
            text-align: center;
            padding-top: 4rem;
        }
        h1 {
          font-size: 40px;
          line-height: 1.05;
          letter-spacing: 0;
        }
        .meta {
          margin: 0;
          color: var(--muted);
          font-size: 14px;
        }
        .search {
          width: min(360px, 100%);
          border: 1px solid var(--line);
          border-radius: 8px;
          background: var(--panel);
          color: var(--text);
          font: inherit;
          padding: 11px 12px;
          outline: none;
          transition: all 0.3s ease;
        }
        .search:focus {
          border-color: var(--accent);
          box-shadow: 0 0 0 3px color-mix(in srgb, var(--accent) 20%, transparent);
        }
        .header-actions {
          display: flex;
          align-items: center;
          gap: 10px;
        }
        .github-link {
          display: inline-flex;
          align-items: center;
          gap: 7px;
          min-height: 44px;
          border: 1px solid var(--line);
          border-radius: 8px;
          background: var(--panel);
          color: var(--text);
          padding: 0 12px;
          font-size: 14px;
          font-weight: 650;
          text-decoration: none;
        }
        .github-link:hover {
          border-color: var(--accent);
          color: var(--accent);
        }
        .bookmark-section {
          padding-top: 32px;
        }
        h2, h3, h4, h5, h6 {
          margin: 0 0 14px;
          font-size: 20px;
          line-height: 1.25;
          letter-spacing: 0;
        }
        .bookmark-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(230px, 1fr));
          gap: 10px;
        }
        .bookmark-card {
          display: grid;
          grid-template-columns: 42px minmax(0, 1fr);
          gap: 12px;
          align-items: center;
          min-height: 66px;
          border-radius: 8px;
          background: var(--panel);
          color: inherit;
          padding: 11px;
          text-decoration: none;
          transition: all 0.3s ease;
        }
        .bookmark-card:hover {
          background: var(--line);
        }
        .bookmark-icon {
          display: grid;
          place-items: center;
          position: relative;
          overflow: hidden;
          width: 42px;
          height: 42px;
          border-radius: 8px;
          background: color-mix(in srgb, var(--accent) 16%, var(--panel));
          color: var(--accent);
          font-weight: 700;
        }
        .bookmark-icon.has-image {
          background: transparent;
          color: inherit;
        }
        .bookmark-icon.has-image.is-loading:not(.is-loaded):not(.is-missing) {
          background: color-mix(in srgb, var(--line) 46%, transparent);
        }
        .bookmark-icon.has-image.is-loading:not(.is-loaded):not(.is-missing)::after {
          content: "";
          position: absolute;
          inset: 0;
          background: linear-gradient(90deg, transparent, color-mix(in srgb, var(--muted) 12%, transparent), transparent);
          transform: translateX(-100%);
          animation: icon-loading 1.2s ease-in-out infinite;
        }
        .bookmark-icon img {
          display: block;
          position: relative;
          z-index: 1;
          width: 34px;
          height: 34px;
          object-fit: contain;
          border-radius: 7px;
          opacity: 0;
          transition: opacity 0.18s ease;
        }
        .bookmark-icon.is-loaded img {
          opacity: 1;
        }
        @keyframes icon-loading {
          to { transform: translateX(100%); }
        }
        @media (prefers-reduced-motion: reduce) {
          .bookmark-icon.has-image::after {
            animation: none;
          }
        }
        .bookmark-content {
          min-width: 0;
        }
        .bookmark-title,
        .bookmark-url {
          display: block;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .bookmark-title {
          font-weight: 650;
        }
        .bookmark-url {
          color: var(--muted);
          font-size: 13px;
        }
        .is-hidden {
          display: none;
        }
        @media (max-width: 680px) {
          main { width: min(100% - 20px, 1160px); padding-top: 24px; }
          header { display: block; }
          h1 { font-size: 32px; }
          .header-actions { margin-top: 18px; align-items: stretch; }
          .search { width: 100%; }
          .github-link { justify-content: center; }
          .bookmark-grid { grid-template-columns: 1fr; }
        }
      </style>
    </head>
    <body>
      <main>
        <header>
          <div>
            <h1>Bookmarks</h1>
          </div>
          <div class="header-actions">
            <input class="search" type="search" placeholder="Search bookmarks" aria-label="Search bookmarks" />
    \(renderGitHubLink(githubURL))
          </div>
        </header>
    \(renderFolder(root))
        <footer>
            <p class="meta">\(total) links · generated \(htmlEscaped(generatedAt))</p>
        </footer>
      </main>
      <script>
        const search = document.querySelector('.search');
        const cards = [...document.querySelectorAll('.bookmark-card')];
        search.addEventListener('input', () => {
          const query = search.value.trim().toLowerCase();
          cards.forEach((card) => {
            const haystack = `${card.dataset.title} ${card.dataset.url}`;
            card.classList.toggle('is-hidden', query && !haystack.includes(query));
          });
        });
      </script>
    </body>
    </html>
    """
}

func generateStaticHTML(projectDir: String, bookmarksDir: String, iconsDir: String, includeGitHubLink: Bool) {
    let outputDir = "\(projectDir)/.html"
    let outputIconsDir = "\(outputDir)/icons"
    let outputPath = "\(outputDir)/index.html"

    do {
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: outputIconsDir) {
            try FileManager.default.removeItem(atPath: outputIconsDir)
        }
    } catch {
        log("❌ 准备静态导航页目录失败: \(error.localizedDescription)")
        exit(1)
    }

    let root = loadBookmarkFolder(path: bookmarksDir, name: "Bookmarks", iconsDir: iconsDir, outputIconsDir: outputIconsDir)
    let githubURL = includeGitHubLink ? currentGitHubURL(projectDir: projectDir) : nil
    if includeGitHubLink && githubURL == nil {
        log("⚠️  未找到可用的 GitHub origin 地址，导航页将不显示 GitHub 链接")
    }
    let html = renderStaticHTML(root: root, githubURL: githubURL)

    do {
        try html.write(toFile: outputPath, atomically: true, encoding: .utf8)
        log("✅ 已生成静态导航页: \(outputPath)")
    } catch {
        log("❌ 生成静态导航页失败: \(error.localizedDescription)")
        exit(1)
    }
}

@discardableResult
func runCommand(_ executable: String, _ arguments: [String], currentDirectory: String) -> (status: Int32, output: String) {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return (1, error.localizedDescription)
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
}

func copyDirectoryContents(from source: String, to destination: String) {
    do {
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
        let items = try FileManager.default.contentsOfDirectory(atPath: source)

        for item in items {
            let sourcePath = "\(source)/\(item)"
            let destinationPath = "\(destination)/\(item)"

            if FileManager.default.fileExists(atPath: destinationPath) {
                try FileManager.default.removeItem(atPath: destinationPath)
            }
            try FileManager.default.copyItem(atPath: sourcePath, toPath: destinationPath)
        }
    } catch {
        log("❌ 复制 .html 内容失败: \(error.localizedDescription)")
        exit(1)
    }
}

func cleanGHPagesWorktreeRoot(_ path: String) {
    do {
        let items = try FileManager.default.contentsOfDirectory(atPath: path)
        for item in items where item != ".git" {
            try FileManager.default.removeItem(atPath: "\(path)/\(item)")
        }
    } catch {
        log("❌ 清理 gh-pages worktree 失败: \(error.localizedDescription)")
        exit(1)
    }
}

func publishHTMLToGHPages(projectDir: String) {
    let sourceHTMLDir = "\(projectDir)/.html"
    let sourceIndexPath = "\(sourceHTMLDir)/index.html"
    guard FileManager.default.fileExists(atPath: sourceIndexPath) else {
        log("❌ 未找到静态页面: \(sourceIndexPath)")
        log("请先运行 ./bkm --generate-html")
        exit(1)
    }

    let tempDir = "\(NSTemporaryDirectory())bookmarks-gh-pages-\(UUID().uuidString)"
    let branchCheck = runCommand("/usr/bin/git", ["rev-parse", "--verify", "gh-pages"], currentDirectory: projectDir)
    let hasBranch = branchCheck.status == 0

    let addResult: (status: Int32, output: String)
    if hasBranch {
        addResult = runCommand("/usr/bin/git", ["worktree", "add", tempDir, "gh-pages"], currentDirectory: projectDir)
    } else {
        addResult = runCommand("/usr/bin/git", ["worktree", "add", "--detach", tempDir, "HEAD"], currentDirectory: projectDir)
    }

    guard addResult.status == 0 else {
        log("❌ 创建 gh-pages worktree 失败:\n\(addResult.output)")
        exit(1)
    }

    defer {
        _ = runCommand("/usr/bin/git", ["worktree", "remove", "--force", tempDir], currentDirectory: projectDir)
    }

    if !hasBranch {
        let orphanResult = runCommand("/usr/bin/git", ["checkout", "--orphan", "gh-pages"], currentDirectory: tempDir)
        guard orphanResult.status == 0 else {
            log("❌ 创建 gh-pages 分支失败:\n\(orphanResult.output)")
            exit(1)
        }
        _ = runCommand("/usr/bin/git", ["rm", "-rf", "."], currentDirectory: tempDir)
    }

    cleanGHPagesWorktreeRoot(tempDir)
    copyDirectoryContents(from: sourceHTMLDir, to: tempDir)
    do {
        try "".write(toFile: "\(tempDir)/.nojekyll", atomically: true, encoding: .utf8)
    } catch {
        log("❌ 写入 .nojekyll 失败: \(error.localizedDescription)")
        exit(1)
    }

    let addHTMLResult = runCommand("/usr/bin/git", ["add", "-A", "-f", "."], currentDirectory: tempDir)
    guard addHTMLResult.status == 0 else {
        log("❌ 暂存 gh-pages 静态资源失败:\n\(addHTMLResult.output)")
        exit(1)
    }

    let statusResult = runCommand("/usr/bin/git", ["status", "--porcelain"], currentDirectory: tempDir)
    guard statusResult.status == 0 else {
        log("❌ 检查 gh-pages 状态失败:\n\(statusResult.output)")
        exit(1)
    }

    if statusResult.output.isEmpty {
        log("ℹ️  gh-pages 分支根目录中的静态资源没有变化")
        return
    }

    let commitResult = runCommand("/usr/bin/git", ["commit", "-m", "chore: update static bookmark page"], currentDirectory: tempDir)
    guard commitResult.status == 0 else {
        log("❌ 提交 gh-pages 分支失败:\n\(commitResult.output)")
        exit(1)
    }

    log("✅ 已将 .html/ 内容提交到 gh-pages 分支根目录")
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
    let arguments = Array(CommandLine.arguments.dropFirst())

    if arguments.contains(Command.help.rawValue) || arguments.contains("-h") {
        print("""
        Usage:
          ./bkm
          ./bkm --set-icons
          ./bkm --generate-html
          ./bkm --generate-html --include-github-link
          ./bkm --publish-gh-pages
          ./bkm --help

        Options:
          --set-icons          Set custom icons for .webloc files. This is the default behavior.
          --generate-html      Generate a static bookmark navigation page at .html/index.html.
          --publish-gh-pages   Commit existing .html contents to the gh-pages branch root.
          --include-github-link
                               Include the current GitHub repository link in generated HTML.
        """)
        return
    }

    let supportedArguments = Set([
        Command.setIcons.rawValue,
        Command.generateHTML.rawValue,
        Command.publishGHPages.rawValue,
        Command.includeGitHubLink.rawValue,
        Command.help.rawValue,
        "-h"
    ])

    let unknownArguments = arguments.filter { !supportedArguments.contains($0) }
    if !unknownArguments.isEmpty {
        log("❌ 未知参数: \(unknownArguments.joined(separator: ", "))")
        log("运行 ./bkm --help 查看可用参数")
        exit(1)
    }

    log("📁 项目目录: \(projectDir)")
    log("📁 Bookmarks目录: \(bookmarksDir)")
    let includeGitHubLink = arguments.contains(Command.includeGitHubLink.rawValue)

    // 检查目录是否存在
    guard FileManager.default.fileExists(atPath: bookmarksDir) else {
        log("❌ bookmarks 目录不存在: \(bookmarksDir)")
        exit(1)
    }

    if arguments.contains(Command.generateHTML.rawValue) {
        generateStaticHTML(projectDir: projectDir, bookmarksDir: bookmarksDir, iconsDir: iconsDir, includeGitHubLink: includeGitHubLink)
        return
    }

    if arguments.contains(Command.publishGHPages.rawValue) {
        publishHTMLToGHPages(projectDir: projectDir)
        return
    }

    log("📁 Icons目录: \(iconsDir)")

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

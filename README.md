Menuist Bookmarks
===

本项目提供了 [Menuist](https://github.com/jaywcjlove/rightmenu-master) 使用的书签数据。只需将本项目的 `bookmarks` 文件夹添加到 Menuist 的常用目录中，即可快速生成一个网站导航菜单，方便快速打开常用网站。

项目中的书签使用 macOS 和 iOS 系统的 `.webloc` 文件格式存储，每个 `.webloc` 文件都是一个指向特定 URL 的快捷方式。通过文件夹对网站进行分类，再结合 Menuist 的常用目录导航功能，可以快速访问整理好的网站列表，实现类似网站导航的体验。

## 目录结构

```shell
├── bookmarks/          # 存放 .webloc 文件（支持子文件夹）
│   ├── .menuistrc.     # Menuist 配置
│   ├── GitHub.webloc
│   ├── Gmail.webloc
│   ├── AI/             # 支持子文件夹
│   │   ├── ChatGPT.webloc
│   │   ├── Claude.webloc
│   │   └── ...
│   ├── Social Media/
│   │   ├── Facebook.webloc
│   │   └── ...
│   └── ...
├── icons/              # 存放图标文件
│   ├── github.com.icns
│   ├── google.com.icns
│   ├── chatgpt.com.icns
│   └── ...
├── set_icons.swift     # Swift 源码
├── build.sh           # 编译脚本
└── set_icons          # 编译后的二进制文件
```

## webloc 文件图标设置

脚本可以自动为 `.webloc` 文件设置图标，根据网址的域名从 `icons` 目录中匹配对应的图标文件。

### 方法1: 直接运行 Swift 脚本 (需要安装 Swift)

```bash
swift set_icons.swift
```

### 方法2: 编译成二进制文件 (推荐)

如果没有 swift 环境运行 swift 脚本，可以直接运行 `./set_icons` 命令文件设置文件图标

```bash
# 编译
./build.sh

# 或者手动编译，生成二进制文件
swiftc -o set_icons set_icons.swift

# 运行
./set_icons
```

## License

MIT © [Kenny Wong](https://wangchujiang.com)

#!/bin/bash

# 编译 Swift 脚本为二进制文件
echo "🔨 正在编译 Swift 脚本..."

# 编译 Swift 源码为二进制可执行文件
swiftc -o set_icons set_icons.swift

if [ $? -eq 0 ]; then
    echo "✅ 编译成功！"
    echo ""
    echo "📦 生成的文件信息:"
    ls -la set_icons
    echo ""
    echo "🏗️  架构信息:"
    file set_icons
    echo ""
    echo "🚀 现在你可以运行: ./set_icons"
    echo ""
    echo "💡 这个二进制文件可以在没有安装 Swift 开发工具的 macOS 系统上运行"
else
    echo "❌ 编译失败"
    exit 1
fi

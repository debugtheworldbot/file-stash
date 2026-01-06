#!/bin/bash

# FileStash DMG 打包脚本

set -e

# 配置
APP_NAME="FileStash"
SCHEME="FileStash"
PROJECT="FileStash.xcodeproj"
CONFIGURATION="Release"
BUILD_DIR="build"
DMG_DIR="$BUILD_DIR/dmg"
OUTPUT_DIR="$BUILD_DIR/output"

# 获取脚本所在目录的上级目录（项目根目录）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "📦 开始打包 $APP_NAME..."

# 清理旧的构建
echo "🧹 清理旧的构建..."
rm -rf "$BUILD_DIR"
mkdir -p "$DMG_DIR" "$OUTPUT_DIR"

# 构建 Release 版本
echo "🔨 构建 Release 版本..."
xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    archive \
    CODE_SIGN_IDENTITY="-" \
    | xcpretty || xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    archive \
    CODE_SIGN_IDENTITY="-"

# 导出 .app
echo "📤 导出应用..."
APP_PATH="$BUILD_DIR/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ 构建失败：找不到 $APP_PATH"
    exit 1
fi

# 复制到 DMG 目录
cp -R "$APP_PATH" "$DMG_DIR/"

# Ad-hoc 签名（重要：确保辅助功能权限正常工作）
echo "🔏 签名应用..."
ENTITLEMENTS="$PROJECT_DIR/FileStash/FileStash.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
    codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$DMG_DIR/$APP_NAME.app"
else
    codesign --force --deep --sign - "$DMG_DIR/$APP_NAME.app"
fi

# 创建 Applications 文件夹的符号链接
ln -s /Applications "$DMG_DIR/Applications"

# 获取版本号
VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")
BUILD_NUMBER=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "1")

DMG_NAME="${APP_NAME}_${VERSION}_${BUILD_NUMBER}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

# 创建 DMG
echo "💿 创建 DMG..."
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

# 清理临时文件
echo "🧹 清理临时文件..."
rm -rf "$DMG_DIR"
rm -rf "$BUILD_DIR/DerivedData"
rm -rf "$BUILD_DIR/$APP_NAME.xcarchive"

# 完成
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo ""
echo "✅ 打包完成！"
echo "📍 位置: $DMG_PATH"
echo "📊 大小: $DMG_SIZE"
echo ""

# 打开输出目录
open "$OUTPUT_DIR"

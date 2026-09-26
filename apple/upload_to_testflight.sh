#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "============================================="
echo "🚀 Automated TestFlight Build & Upload Script"
echo "============================================="

# 1. Regenerate project if needed
echo "⚙️  Validating Xcode project..."
xcodegen generate > /dev/null

# 2. Build & Archive iOS
echo ""
echo "📱 Archiving iOS Target (com.davidpoka.ytaudiodownloader.ios)..."
mkdir -p build
xcodebuild -project YTAudioDownloader.xcodeproj \
  -scheme YTAudioDownloader-iOS \
  -archivePath build/iOS.xcarchive \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates \
  archive -quiet

echo "✅ iOS Archive completed successfully!"

# 3. Build & Archive macOS
echo ""
echo "💻 Archiving macOS Target (com.davidpoka.ytaudiodownloader.mac)..."
xcodebuild -project YTAudioDownloader.xcodeproj \
  -scheme YTAudioDownloader-macOS \
  -archivePath build/macOS.xcarchive \
  -destination "generic/platform=macOS" \
  -allowProvisioningUpdates \
  archive -quiet

echo "✅ macOS Archive completed successfully!"

# 4. Upload to App Store Connect / TestFlight
echo ""
echo "☁️  Uploading iOS to TestFlight..."
xcodebuild -exportArchive \
  -archivePath build/iOS.xcarchive \
  -exportPath build/iOS_export \
  -exportOptionsPlist exportOptions_upload.plist \
  -allowProvisioningUpdates

echo "☁️  Uploading macOS to TestFlight..."
xcodebuild -exportArchive \
  -archivePath build/macOS.xcarchive \
  -exportPath build/macOS_export \
  -exportOptionsPlist exportOptions_upload.plist \
  -allowProvisioningUpdates

echo ""
echo "🎉 Both iOS and macOS builds successfully submitted to TestFlight!"

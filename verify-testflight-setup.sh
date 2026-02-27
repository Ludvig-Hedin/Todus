#!/bin/bash

##################################################################
# TestFlight Setup Verification Script
# Purpose: Verify that all prerequisites are met before building
# Usage: bash verify-testflight-setup.sh
##################################################################

echo "🔍 Todus TestFlight Verification Script"
echo "======================================="
echo ""

PASSED=0
FAILED=0
WARNING=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

check_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    ((PASSED++))
}

check_fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    ((FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠️  WARN${NC}: $1"
    ((WARNING++))
}

check_info() {
    echo -e "${BLUE}ℹ️  INFO${NC}: $1"
}

echo "📋 1. System & Environment Checks"
echo "-----------------------------------"

# Check Xcode
if xcode-select -p > /dev/null 2>&1; then
    XCODE_PATH=$(xcode-select -p)
    check_pass "Xcode installed at: $XCODE_PATH"
else
    check_fail "Xcode not installed or not configured"
fi

# Check Xcode version
if command -v xcodebuild &> /dev/null; then
    XCODE_VERSION=$(xcodebuild -version | grep "Xcode" | awk '{print $2}')
    check_pass "Xcode version: $XCODE_VERSION"
else
    check_fail "xcodebuild command not available"
fi

# Check Ruby (needed for CocoaPods if any)
if command -v ruby &> /dev/null; then
    RUBY_VERSION=$(ruby -v)
    check_pass "Ruby available: $(echo $RUBY_VERSION | cut -d' ' -f1-2)"
else
    check_warn "Ruby not installed (may be needed for CocoaPods)"
fi

echo ""
echo "📦 2. Project Structure Checks"
echo "------------------------------"

PROJECT_PATH="/Users/ludvighedin/Programming/personal/mail/apps/apple/Todus"

if [ -d "$PROJECT_PATH" ]; then
    check_pass "Project directory found: $PROJECT_PATH"
else
    check_fail "Project directory not found at: $PROJECT_PATH"
    exit 1
fi

if [ -f "$PROJECT_PATH/Todus.xcodeproj/project.pbxproj" ]; then
    check_pass "Xcode project file found"
else
    check_fail "Xcode project file not found"
fi

if [ -f "$PROJECT_PATH/Todus/TodusApp.swift" ]; then
    check_pass "SwiftUI app entry point found"
else
    check_fail "TodusApp.swift not found"
fi

if [ -f "$PROJECT_PATH/Todus/ContentView.swift" ]; then
    check_pass "ContentView (WebView wrapper) found"
else
    check_fail "ContentView.swift not found"
fi

if [ -d "$PROJECT_PATH/Todus/Assets.xcassets" ]; then
    check_pass "Asset catalog found"
else
    check_fail "Asset catalog not found"
fi

echo ""
echo "🔐 3. Code Signing Checks"
echo "-------------------------"

# Check for signing certificates
if security find-certificate -c "Apple Distribution" > /dev/null 2>&1; then
    check_pass "Apple Distribution certificate found in Keychain"
else
    check_warn "Apple Distribution certificate not found - you'll need to create it in Apple Developer"
fi

# Check for provisioning profiles
PROFILES_PATH="$HOME/Library/MobileDevice/Provisioning\ Profiles"
if [ -d "$PROFILES_PATH" ]; then
    PROFILE_COUNT=$(ls "$PROFILES_PATH" 2>/dev/null | wc -l)
    if [ "$PROFILE_COUNT" -gt 0 ]; then
        check_pass "Provisioning profiles found: $PROFILE_COUNT profile(s)"
    else
        check_warn "No provisioning profiles found - you'll need to create them in Apple Developer"
    fi
else
    check_warn "Provisioning profiles directory not found"
fi

echo ""
echo "🌐 4. Network & Connectivity Checks"
echo "-----------------------------------"

# Check internet connectivity
if ping -c 1 developer.apple.com > /dev/null 2>&1; then
    check_pass "Can reach developer.apple.com"
else
    check_fail "Cannot reach developer.apple.com - check internet connection"
fi

if ping -c 1 appstoreconnect.apple.com > /dev/null 2>&1; then
    check_pass "Can reach appstoreconnect.apple.com"
else
    check_fail "Cannot reach appstoreconnect.apple.com - check internet connection"
fi

if ping -c 1 todus-production.ludvighedin15.workers.dev > /dev/null 2>&1; then
    check_pass "Can reach production web app URL"
else
    check_fail "Cannot reach production web app - app will fail at runtime"
fi

echo ""
echo "📱 5. App Configuration Checks"
echo "------------------------------"

# Check Info.plist
if grep -q "CFBundleName" "$PROJECT_PATH/Todus/Info.plist"; then
    check_pass "Info.plist properly configured"
else
    check_warn "Info.plist may need review"
fi

# Check for hardcoded URLs
if grep -q "todus-production.ludvighedin15.workers.dev" "$PROJECT_PATH/Todus/ContentView.swift"; then
    check_pass "Web app URL configured in ContentView"
else
    check_warn "Web app URL not found - check ContentView.swift"
fi

if grep -q "todus://" "$PROJECT_PATH/Todus/ContentView.swift"; then
    check_pass "OAuth callback scheme configured"
else
    check_warn "OAuth callback scheme not found"
fi

echo ""
echo "📋 6. Pre-TestFlight Checklist"
echo "------------------------------"

echo ""
echo "Before you build, have you completed:"
echo ""
read -p "[ ] Created Apple Distribution certificate in Apple Developer? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    check_warn "Certificate not created - see TESTFLIGHT_DEPLOYMENT_GUIDE.md Part 3"
else
    check_pass "Certificate created"
fi

read -p "[ ] Created provisioning profiles for App Store? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    check_warn "Provisioning profiles not created - see TESTFLIGHT_DEPLOYMENT_GUIDE.md Part 3"
else
    check_pass "Provisioning profiles created"
fi

read -p "[ ] Registered App IDs in Apple Developer? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    check_warn "App IDs not registered - see TESTFLIGHT_DEPLOYMENT_GUIDE.md Part 2"
else
    check_pass "App IDs registered"
fi

read -p "[ ] Created app records in App Store Connect? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    check_warn "App records not created - see TESTFLIGHT_DEPLOYMENT_GUIDE.md Part 2"
else
    check_pass "App records created"
fi

read -p "[ ] Configured signing in Xcode (Team, Bundle ID, Certificate)? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    check_warn "Xcode signing not configured - see TESTFLIGHT_DEPLOYMENT_GUIDE.md Part 3"
else
    check_pass "Xcode signing configured"
fi

echo ""
echo "======================================="
echo "📊 Summary"
echo "======================================="
echo -e "${GREEN}✅ Passed:${NC} $PASSED"
echo -e "${RED}❌ Failed:${NC} $FAILED"
echo -e "${YELLOW}⚠️  Warnings:${NC} $WARNING"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed! Ready to build.${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Open Xcode: open $PROJECT_PATH/Todus.xcodeproj"
    echo "2. Select scheme: Todus"
    echo "3. Select destination: Generic iOS Device"
    echo "4. Menu: Product → Archive"
    echo "5. In Organizer: Distribute → App Store Connect → Upload"
    echo ""
    exit 0
else
    echo -e "${RED}❌ Some checks failed. Please fix the above issues.${NC}"
    echo ""
    echo "See TESTFLIGHT_DEPLOYMENT_GUIDE.md for detailed instructions."
    echo ""
    exit 1
fi

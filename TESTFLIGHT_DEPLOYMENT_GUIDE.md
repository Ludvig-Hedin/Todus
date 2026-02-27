# TestFlight Deployment Guide for Todus (iOS & macOS)

**Date:** 2026-02-24
**Status:** Ready for deployment
**Last Updated:** 2026-02-24

---

## Overview

This guide provides step-by-step instructions to deploy the Todus app to TestFlight for iOS and macOS. The app uses a native Swift WebView wrapper around the production web application.

**Key Facts:**
- **App Type:** Native Swift iOS/macOS app wrapping web app in WKWebView
- **Location:** `/Users/ludvighedin/Programming/personal/mail/apps/apple/Todus/`
- **Platforms:** iOS 14+ and macOS 11+
- **Xcode Version:** 26.0.1 (Build 17A400)
- **Web App URL:** `https://todus-production.ludvighedin15.workers.dev`
- **Backend URL:** `https://todus-server-v1-production.ludvighedin15.workers.dev`

---

## Part 1: Prerequisites Checklist

Before starting, ensure you have:

- [ ] **Apple Developer Account** with Admin/Account Holder role
- [ ] **Xcode 26.0.1+** installed on your Mac
- [ ] **App Store Connect** access
- [ ] Valid **Apple Developer Certificate** for distribution
- [ ] **Provisioning Profiles** for App Store distribution
- [ ] **Team ID** from Apple Developer account
- [ ] Access to **macOS machine** for code signing (required for testflight archive)

---

## Part 2: Bundle ID Setup

### Current Status
- **iOS Bundle ID:** `com.zero.nativeapp` (defined in Xcode project)
- **macOS Bundle ID:** `org.reactjs.native.ZeroNative` (placeholder)

### What You Need to Do

#### 2.1 Choose Final Bundle IDs (If Not Using Above)

Recommended format:
```
iOS:   com.ludvighedin.todus.ios
macOS: com.ludvighedin.todus.macos
```

#### 2.2 Register App IDs in Apple Developer

1. Visit [Apple Developer - Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)
2. Click the "+" button to create new identifiers
3. Select "App IDs" → Continue
4. Configure:
   - **Platform:** iOS
   - **Description:** Todus iOS Native
   - **Bundle ID:** (choose from above or use `com.zero.nativeapp`)
   - **Capabilities:** (leave default for now)
5. Repeat for macOS with `Capabilities: None` selected

#### 2.3 Create App Records in App Store Connect

1. Visit [App Store Connect - Apps](https://appstoreconnect.apple.com/apps)
2. Click "New App"
3. Fill in:
   - **Platform:** iOS (do this twice, once for iOS and once for macOS)
   - **Name:** Todus
   - **Bundle ID:** (select the ID you created above)
   - **SKU:** `TODUS-iOS` or `TODUS-macOS`
   - **User Access:** Full Access
4. Create app records for both platforms

---

## Part 3: Code Signing Setup

### 3.1 Create Distribution Certificates

1. In [Apple Developer Account](https://developer.apple.com/account/resources/certificates/list):
   - Click "+"
   - Select "Apple Distribution"
   - Follow prompts to create certificate using Keychain
   - Download and install certificate locally

**Do this for:**
- [ ] iOS Distribution Certificate
- [ ] macOS Distribution Certificate

### 3.2 Create Provisioning Profiles

1. Go to [Provisioning Profiles](https://developer.apple.com/account/resources/profiles/list)
2. Click "+"
3. Select "App Store" as the type
4. Select the App ID you created
5. Select the distribution certificate
6. Name it: `Todus iOS AppStore` (or `Todus macOS AppStore`)
7. Download and install the profile

**Do this for:**
- [ ] iOS App Store Profile
- [ ] macOS App Store Profile

### 3.3 Update Xcode Project Settings

#### iOS Target (Todus)

1. Open `/Users/ludvighedin/Programming/personal/mail/apps/apple/Todus/Todus.xcodeproj`
2. Select target `Todus`
3. Go to **Signing & Capabilities**
4. Set:
   - **Team:** Your Apple Team
   - **Bundle Identifier:** Your chosen iOS bundle ID
   - **Signing Certificate:** Apple Distribution
   - **Provisioning Profile:** Todus iOS AppStore

#### macOS Target (Todus for macOS)

1. In same project, create or select macOS target (if not present)
2. Set same signing settings but for macOS profiles

---

## Part 4: Build Configuration

### 4.1 Verify Build Settings

Before building, verify your machine has proper setup:

```bash
# Check Xcode version
xcodebuild -version

# Expected: Xcode 26.0.1 or later

# Test compile (no signing required)
cd /Users/ludvighedin/Programming/personal/mail/apps/apple/Todus
xcodebuild -project Todus.xcodeproj \
  -scheme Todus \
  -configuration Release \
  -destination generic/platform=iOS \
  CODE_SIGNING_ALLOWED=NO \
  build
```

---

## Part 5: Building for TestFlight

### 5.1 Build iOS Archive

1. **Open Xcode:**
   ```bash
   open /Users/ludvighedin/Programming/personal/mail/apps/apple/Todus/Todus.xcodeproj
   ```

2. **Select scheme and destination:**
   - Scheme: `Todus`
   - Destination: `Generic iOS Device`

3. **Build Archive:**
   - Menu: `Product` → `Archive`
   - Wait for build to complete

4. **Distribute to App Store Connect:**
   - Organizer window appears after build
   - Click `Distribute App`
   - Select `App Store Connect`
   - Select `Upload`
   - Sign with Apple ID when prompted
   - Click `Upload`

5. **Wait for processing:**
   - App Store Connect → TestFlight → Builds (iOS)
   - Processing takes 5-15 minutes
   - You'll receive email when ready

### 5.2 Build macOS Archive (if applicable)

Same process as iOS, but:
- Destination: `Any Mac`
- Scheme: May need macOS variant if available
- Distribution profile: macOS AppStore profile

---

## Part 6: TestFlight Internal Testing Setup

### 6.1 Create Internal Testers Group

1. Visit [App Store Connect - TestFlight](https://appstoreconnect.apple.com/testers/ios)
2. Click **Internal Testing**
3. Click "Create a Group"
4. Name: `Core Team`
5. Add team members' Apple IDs

### 6.2 Add Build to Internal Testing

1. Once build is processed:
   - Go to TestFlight → iOS/macOS → Builds
   - Select your build
   - Click "Add for Testing"
   - Select "Internal Testing"
   - Select the `Core Team` group
   - Click "Save"

### 6.3 Send Invitations

1. Internal testers will receive email invitation
2. They can download the app via TestFlight app

---

## Part 7: Pre-Flight Testing Checklist

Before sharing TestFlight link to internal testers, you (or designated QA person) should verify:

### Functionality

- [ ] App launches successfully
- [ ] Login screen displays with provider options
- [ ] Google OAuth works (redirects back to app)
- [ ] Session persists across app restart
- [ ] Can access `/mail/inbox` after auth
- [ ] Can read email list
- [ ] Can open and read email threads
- [ ] Can compose new email
- [ ] Settings screens load
- [ ] Logout works and redirects to login
- [ ] No crashes in first 10 minutes of use

### Performance

- [ ] App starts in < 3 seconds on iPhone
- [ ] Scrolling is smooth (60fps)
- [ ] No memory warnings or crashes

### Networking

- [ ] App connects to production backend
- [ ] Data loads correctly
- [ ] Error handling works when offline

---

## Part 8: Manual Verification Workflow

Before TestFlight goes to internal testers:

### Step 1: Personal Testing (You)

1. Download app from TestFlight
2. Run through Pre-Flight Testing Checklist above
3. Document any issues

### Step 2: Internal Tester Invitation

1. Once verified, invite internal team via TestFlight
2. Set feedback deadline (e.g., 24 hours)
3. Request bug reports in dedicated channel

### Step 3: Issue Triage

1. Review reported issues
2. Prioritize critical bugs
3. Fix and rebuild if needed
4. Re-upload build if changes made

---

## Part 9: Common Issues and Fixes

### Issue: "Cannot Code Sign"

**Cause:** Certificate or provisioning profile not installed

**Fix:**
```bash
# Make sure profiles are installed
open ~/Library/MobileDevice/Provisioning\ Profiles/

# Verify certificates
security find-certificate -c "Apple Distribution"
```

### Issue: "App Crashes on Launch"

**Cause:** Likely related to WKWebView config or URL mismatch

**Fix:**
1. Check ContentView.swift - verify URLs match production
2. Check WKWebView configuration in code
3. Verify network connectivity to backend

### Issue: "OAuth Redirect Not Working"

**Cause:** Redirect URL not registered in OAuth provider

**Fix:**
1. Verify `todus://auth-callback` scheme is registered in Xcode target
2. Verify Google OAuth app has this callback configured
3. Check Better Auth trusted origins in server config

### Issue: "Build Upload Fails"

**Cause:** Invalid signing or metadata issues

**Fix:**
1. Verify bundle ID matches App Store Connect app record
2. Verify signing certificate is not expired
3. Verify version number is not already in use
4. Check build number is unique

---

## Part 10: Environment Configuration

### Current Configuration

**Web App URL:** `https://todus-production.ludvighedin15.workers.dev`
**Backend URL:** `https://todus-server-v1-production.ludvighedin15.workers.dev`

These are hardcoded in `ContentView.swift`. No environment changes needed for TestFlight.

### If You Need to Change URLs

Edit `/Users/ludvighedin/Programming/personal/mail/apps/apple/Todus/Todus/ContentView.swift`:

```swift
MailWebView(urlString: "https://YOUR-WEB-URL/mail/inbox")
```

Then rebuild and upload new archive.

---

## Part 11: Release Notes Template

When creating TestFlight build, use this template for release notes:

```
## v1.0.0 (Build XXX) - TestFlight Internal Testing

### What's New
- Initial TestFlight release
- Native iOS/macOS app wrapping production web app
- OAuth login with Google
- Full mail inbox functionality
- Settings and profile management

### Known Limitations
- Keyboard shortcuts limited to macOS
- Some advanced features via web UI only

### Testing Focus
- Please report any crashes
- Test on both iPhone and macOS
- Test offline handling
- Test app restoration after background

### How to Report Issues
- Use feedback button in TestFlight app
- Or report in #bugs Slack channel with:
  - Device and OS version
  - Steps to reproduce
  - Screenshot if applicable
```

---

## Part 12: Rollback Plan

If critical issues found:

1. **Do Not Distribute** to external testers
2. **Fix the issue** in code
3. **Increment build number** in Xcode
4. **Rebuild and re-upload** new archive
5. **Re-test** with same internal tester group
6. **Once verified**, proceed to external testing or release

---

## Part 13: Next Steps After TestFlight Approval

Once internal testing is successful:

1. **Prepare for External Testing** (if needed)
   - Create external tester group
   - Prepare TestFlight release notes
   - Set up feedback collection process

2. **Prepare for App Store Release**
   - Add app screenshots for iOS and macOS
   - Add app description, keywords, category
   - Set pricing and availability
   - Configure subscription details (if applicable)
   - Add privacy policy

3. **Submit for Review**
   - Click "Submit for Review" in App Store Connect
   - Apple reviews submission (2-5 days typical)
   - If approved, app appears on App Store

---

## Part 14: Verification Checklist (Final)

Before sending to testers, verify:

**Code**
- [ ] No console errors in Xcode build output
- [ ] Code signing successful
- [ ] App launches without crashes

**Configuration**
- [ ] Bundle ID matches App Store Connect
- [ ] Team ID correct
- [ ] Certificate and profile installed
- [ ] Version number incremented

**TestFlight**
- [ ] App uploaded successfully
- [ ] Build processed without errors
- [ ] Build assigned to internal tester group
- [ ] Testers received invitation

**Documentation**
- [ ] Release notes added
- [ ] Testing checklist prepared
- [ ] Known issues documented

---

## Quick Reference: Commands

### Test Build (No Signing)
```bash
cd /Users/ludvighedin/Programming/personal/mail/apps/apple/Todus
xcodebuild -project Todus.xcodeproj -scheme Todus -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build
```

### Open in Xcode
```bash
open /Users/ludvighedin/Programming/personal/mail/apps/apple/Todus/Todus.xcodeproj
```

### List Available Schemes
```bash
xcodebuild -list -project Todus.xcodeproj
```

---

## Support & Questions

If you encounter issues:

1. Check Common Issues section (Part 9)
2. Review Apple's [TestFlight Documentation](https://help.apple.com/testflight/)
3. Check Xcode build logs for detailed error messages
4. Verify all prerequisites in Part 1 are complete

---

## Completion Checklist

- [ ] Prerequisites verified (Part 1)
- [ ] Bundle IDs registered (Part 2)
- [ ] Certificates created (Part 3)
- [ ] Xcode project signed (Part 3.3)
- [ ] Build test successful (Part 4)
- [ ] iOS archive built and uploaded (Part 5.1)
- [ ] TestFlight internal group created (Part 6.1)
- [ ] Pre-flight testing completed (Part 7)
- [ ] Internal testers invited (Part 6.2)
- [ ] All issues from Part 7 resolved
- [ ] Ready for external testing or App Store

---

**Status:** ✅ Ready for deployment
**Last Verified:** 2026-02-24

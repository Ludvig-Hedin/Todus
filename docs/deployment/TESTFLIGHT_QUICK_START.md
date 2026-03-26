# TestFlight Quick Start (5-Step Process)

**⏱️ Total Time: 1-2 hours**

This is the fast-track version. For detailed steps, see `TESTFLIGHT_DEPLOYMENT_GUIDE.md`

---

## Step 1: Apple Developer Setup (20 minutes)

### 1.1 Register App IDs
- Visit: https://developer.apple.com/account/resources/identifiers/list
- Create "App ID" for iOS with bundle ID: `com.zero.nativeapp` (or your choice)
- Create "App ID" for macOS with bundle ID: `com.zero.nativeapp.macos`

### 1.2 Create Distribution Certificates
- Visit: https://developer.apple.com/account/resources/certificates/list
- Click "+" and select "Apple Distribution"
- Create certificate for **iOS** (download and install)
- Create certificate for **macOS** (download and install)

### 1.3 Create Provisioning Profiles
- Visit: https://developer.apple.com/account/resources/profiles/list
- Click "+" and select "App Store"
- Create "Todus iOS AppStore" profile (select iOS bundle ID, iOS certificate)
- Create "Todus macOS AppStore" profile (select macOS bundle ID, macOS certificate)
- Download and install both profiles

### 1.4 Create App Records in App Store Connect
- Visit: https://appstoreconnect.apple.com/apps
- Click "New App"
- Create iOS app: Name=Todus, Bundle ID=com.zero.nativeapp, SKU=TODUS-iOS
- Create macOS app: Name=Todus, Bundle ID=com.zero.nativeapp.macos, SKU=TODUS-macOS

---

## Step 2: Xcode Configuration (10 minutes)

### 2.1 Update Xcode Project

```bash
# Open the project
open /Users/ludvighedin/Programming/personal/mail/apps/apple/Todus/Todus.xcodeproj
```

### 2.2 Configure Signing for iOS Target

1. Select target: `Todus`
2. Go to: Signing & Capabilities
3. Set:
   - **Team:** Your Apple Team
   - **Bundle Identifier:** com.zero.nativeapp
   - **Signing Certificate:** Apple Distribution
   - **Provisioning Profile:** Todus iOS AppStore

### 2.3 Configure Signing for macOS Target (if present)

Same as above but with macOS profiles.

---

## Step 3: Build Archive (15 minutes)

### 3.1 Build iOS Archive

```bash
# In Xcode:
# 1. Select scheme: Todus
# 2. Select destination: Generic iOS Device
# 3. Menu: Product → Archive
# 4. Wait for build to complete (usually 5-10 minutes)
```

### 3.2 Distribute to App Store Connect

After build completes in Xcode Organizer:

```bash
# In Organizer window:
# 1. Click "Distribute App"
# 2. Select "App Store Connect"
# 3. Select "Upload"
# 4. Sign in with Apple ID
# 5. Click "Upload"
# 6. Wait for processing (5-15 minutes)
```

### 3.3 Build macOS Archive (same steps, select macOS destination)

---

## Step 4: TestFlight Setup (10 minutes)

### 4.1 Create Internal Tester Group

- Visit: https://appstoreconnect.apple.com/testers/ios
- Click "Create a Group"
- Name: "Core Team"
- Add your Apple ID and any team members

### 4.2 Assign Build to Internal Testing

Once build is processed:
- TestFlight → Builds (iOS/macOS)
- Select your build
- Click "Add for Testing"
- Select "Internal Testing"
- Select "Core Team"
- Click "Save"

### 4.3 Send Invitations

- Testers will receive email from TestFlight
- They download via TestFlight app

---

## Step 5: Pre-Flight Verification (10 minutes)

Before sending to others, test yourself:

### Download & Test
- [ ] App launches without crash
- [ ] See login screen
- [ ] Tap "Sign in with Google"
- [ ] Redirected to Google auth
- [ ] Back to app after auth
- [ ] Can see inbox
- [ ] Can open email
- [ ] Logout works
- [ ] No crashes in 5 minutes of use

---

## ✅ Done!

Your app is now on TestFlight and ready for internal testing.

**Next:**
- Invite team members
- Collect feedback
- Fix bugs if needed
- Re-upload new build if changes made

---

## Common Mistakes (Don't Do These!)

❌ **Don't use** "iOS App Development" certificate (use "Apple Distribution")
❌ **Don't use** wrong bundle ID (must match App Store Connect)
❌ **Don't forget** to download and install provisioning profiles
❌ **Don't sign** with personal team on business app (select correct team)
❌ **Don't increment** version instead of build number between uploads

---

## If Something Fails

| Error | Solution |
|-------|----------|
| "Code Sign Error" | Check Team ID, Bundle ID, and signing certificate are all set |
| "Invalid Provisioning" | Download and reinstall provisioning profiles |
| "Build Already Exists" | Increment build number in Xcode and rebuild |
| "Upload Failed" | Verify bundle ID matches App Store Connect app record |
| "OAuth Not Working" | Verify `todus://` scheme registered in Google OAuth |

---

## Need More Details?

See **TESTFLIGHT_DEPLOYMENT_GUIDE.md** for:
- Detailed instructions with screenshots
- Troubleshooting guide
- Configuration options
- Release notes template

---

**Status:** 🟢 Ready to start
**Time to completion:** 1-2 hours
**Next action:** Step 1 - Apple Developer Setup

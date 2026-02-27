# 🚀 Getting Todus to TestFlight - Complete Guide

**Status:** Code Ready | Deployment Guide Ready
**Time to TestFlight:** 1-2 hours
**Difficulty:** Medium (mostly Apple Developer portal navigation)

---

## 📚 Documentation You Have

I've created 4 comprehensive documents to help you:

1. **TESTFLIGHT_QUICK_START.md** ⭐ START HERE
   - 5-step process
   - Fastest path to TestFlight
   - 1-2 hours total

2. **TESTFLIGHT_DEPLOYMENT_GUIDE.md** (Detailed)
   - Complete step-by-step guide
   - Troubleshooting section
   - Reference material

3. **APP_BUILD_STATUS.md** (Technical Overview)
   - Current app architecture
   - What's completed
   - What requires manual steps

4. **verify-testflight-setup.sh** (Verification Script)
   - Checks your environment
   - Verifies prerequisites
   - Can run anytime to verify setup

---

## 🎯 Your Next Steps (In Order)

### Phase 1: Understanding (5 minutes)
- [ ] Read TESTFLIGHT_QUICK_START.md completely
- [ ] Understand the 5-step process
- [ ] Gather your Apple Developer account info

### Phase 2: Apple Developer Setup (20 minutes)
- [ ] Go to developer.apple.com
- [ ] Create App IDs (iOS and macOS)
- [ ] Create Distribution Certificates
- [ ] Create Provisioning Profiles
- [ ] Create App Store Connect records

### Phase 3: Xcode Configuration (10 minutes)
- [ ] Open Xcode project
- [ ] Configure signing for iOS target
- [ ] Set bundle ID
- [ ] Set team
- [ ] Set signing certificate

### Phase 4: Build & Upload (20 minutes)
- [ ] Build archive in Xcode
- [ ] Upload to App Store Connect
- [ ] Wait for processing

### Phase 5: TestFlight Setup (10 minutes)
- [ ] Create internal tester group
- [ ] Add testers
- [ ] Send invitations

---

## 📍 Where the App Is Located

```
/Users/ludvighedin/Programming/personal/mail/apps/apple/Todus/
├── Todus.xcodeproj          <- Open this in Xcode
├── Todus/
│   ├── TodusApp.swift       <- App entry point
│   ├── ContentView.swift     <- Main WebView wrapper
│   └── Assets.xcassets/     <- App icons
```

---

## 🔑 Key Information About Your App

### What It Is
- **Native Swift iOS and macOS app**
- **WebView wrapper** around production web app
- **Full OAuth support** with Google login
- **No external dependencies**

### What It Does
- Shows email inbox
- Allows reading emails
- Allows composing emails
- Provides full settings access
- Handles OAuth authentication

### URLs
```
Web App: https://todus-production.ludvighedin15.workers.dev
Backend: https://todus-server-v1-production.ludvighedin15.workers.dev
OAuth Callback: todus://auth-callback
```

### Bundle IDs
```
iOS:   com.zero.nativeapp
macOS: com.zero.nativeapp.macos (or your choice)
```

---

## ✅ Verification Checklist

Before you start, have these ready:

### Account & Access
- [ ] Apple Developer account with Admin role
- [ ] App Store Connect access
- [ ] Ability to create certificates
- [ ] Ability to create provisioning profiles

### Technical Prerequisites
- [ ] Xcode 26.0.1+ installed
- [ ] Swift 5.9+ (comes with Xcode)
- [ ] Internet connection
- [ ] Admin access on Mac (for Keychain)

### Optional but Helpful
- [ ] Apple Developer phone app (for push notification testing)
- [ ] TestFlight app on iPhone/Mac (to test downloaded app)
- [ ] Team members' Apple IDs (for internal testers)

---

## 📖 Reading Order (Recommended)

1. **TESTFLIGHT_QUICK_START.md** (5 min)
   - Overview of 5 steps
   - Quick reference URLs

2. **TESTFLIGHT_DEPLOYMENT_GUIDE.md** (15 min)
   - Detailed walkthrough
   - Screenshots references
   - Troubleshooting

3. **APP_BUILD_STATUS.md** (optional)
   - Technical details
   - Architecture info
   - Post-TestFlight roadmap

4. **verify-testflight-setup.sh** (anytime)
   - Run to verify environment
   - Check prerequisites
   - Confirm all systems ready

---

## 🆘 Help & Troubleshooting

### Quick Fixes for Common Issues

**"I don't know my Team ID"**
- Go to developer.apple.com
- Account Settings (top right)
- Team ID is shown under Membership Details

**"Can't find provisioning profiles"**
- You haven't downloaded them yet
- After creating in Apple Developer, you MUST download
- Double-click to install them

**"Xcode says code signing failed"**
- Check Team ID matches your account
- Check Bundle ID is registered
- Check provisioning profile is installed
- See Part 9 in TESTFLIGHT_DEPLOYMENT_GUIDE.md

**"Build upload failed"**
- Increment build number (not version)
- Check bundle ID matches App Store Connect
- Check version number isn't already used

### Where to Get Help

- **Apple Support:** help.apple.com
- **Xcode Documentation:** See Help menu in Xcode
- **App Store Connect Help:** help.apple.com/app-store-connect
- **This Repository:** See TESTFLIGHT_DEPLOYMENT_GUIDE.md Part 9

---

## ⏱️ Timeline

| Phase | Time | What You Do |
|-------|------|-----------|
| Read Docs | 15 min | Read this file + Quick Start |
| Apple Developer | 20 min | Create IDs, certs, profiles |
| Xcode Config | 10 min | Configure signing |
| Build | 15 min | Archive in Xcode |
| Upload | 5 min | Send to TestFlight |
| Processing | 10 min | Wait for Apple (automatic) |
| Testing | 10 min | Download and test |
| **TOTAL** | **85 min** | ≈ **1.5 hours** |

---

## 🚦 Traffic Light System (Current Status)

### 🟢 READY TO GO
- [x] App code complete
- [x] Swift syntax checked
- [x] Assets prepared
- [x] URLs configured
- [x] OAuth integration done

### 🟡 AWAITING YOUR ACTION
- [ ] Apple Developer setup
- [ ] Code signing configuration
- [ ] Build archive creation
- [ ] TestFlight upload

### 🔴 NOT IN SCOPE (Post-Launch)
- [ ] Push notifications
- [ ] Biometric auth
- [ ] Offline mode
- [ ] Native UI rebuild

---

## 💡 Pro Tips

### Tip 1: Keep Passwords Safe
When creating certificates:
- **Don't** save the CSR (Certificate Signing Request) anywhere public
- **DO** store the downloaded certificate in your secure location
- **DO** backup your private key

### Tip 2: Version Management
- **Version Number:** Only increment for App Store releases (e.g., 1.0, 1.1)
- **Build Number:** Increment for each TestFlight upload (e.g., 1, 2, 3...)

### Tip 3: Efficient Testing
Instead of waiting for App Store review:
- Use **Internal Testing** first (instant)
- Share with team via TestFlight
- Get feedback before public release

### Tip 4: Archive Organization
Keep each archive build:
- Note the build date
- Note what's included
- Makes rollback easier if needed

### Tip 5: Backup Credentials
After setup, backup:
- Certificates (as .p12 files)
- Provisioning profiles
- Private keys
- In case you need to rebuild on another machine

---

## 🎓 Learning Resources

If you want to understand the process better:

1. **Apple Developer Documentation:**
   - [Create your app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/)
   - [Managing your app's capabilities](https://developer.apple.com/documentation/xcode/managing-your-apps-capabilities/)
   - [Signing your app](https://developer.apple.com/documentation/xcode/signing-your-app/)

2. **YouTube Tutorials:**
   - Search "App Store Connect setup 2026"
   - Search "Xcode code signing setup"
   - Look for official Apple Developer channel videos

3. **This Repository:**
   - TESTFLIGHT_DEPLOYMENT_GUIDE.md - comprehensive guide
   - APP_BUILD_STATUS.md - technical details

---

## 📞 Next Steps (Action Items)

### Right Now (Next 5 minutes)
1. [ ] Read TESTFLIGHT_QUICK_START.md
2. [ ] Bookmark TESTFLIGHT_DEPLOYMENT_GUIDE.md
3. [ ] Open Apple Developer in browser

### Within 1 Hour
1. [ ] Start Phase 1-2 of TESTFLIGHT_QUICK_START.md
2. [ ] Create App IDs on Apple Developer
3. [ ] Create Distribution Certificates

### Within 2 Hours
1. [ ] Create Provisioning Profiles
2. [ ] Create App Store Connect records
3. [ ] Configure Xcode signing
4. [ ] Build archive
5. [ ] Upload to TestFlight

### Day 2 (Next Business Day)
1. [ ] Create internal tester group
2. [ ] Invite team members
3. [ ] Test app
4. [ ] Gather feedback

---

## 🎉 Success Looks Like

You'll know you've succeeded when:

✅ **Build Uploaded**
- App Store Connect shows your build in Builds tab
- Status shows "Processing" or "Ready for Testing"

✅ **TestFlight Ready**
- Build status shows "Ready for Testing"
- Internal Testing group created with testers added
- Testers receive invitation email

✅ **App Works**
- Can download from TestFlight
- Launches without crash
- Can log in
- Can see inbox

---

## 📝 Document Summary Table

| Document | Purpose | Read When |
|----------|---------|-----------|
| **TESTFLIGHT_QUICK_START.md** | 5-step overview | Starting out, quick reference |
| **TESTFLIGHT_DEPLOYMENT_GUIDE.md** | Detailed instructions | Need detailed help |
| **APP_BUILD_STATUS.md** | Technical details | Want to understand architecture |
| **verify-testflight-setup.sh** | Environment check | Before attempting to build |
| **GETTING_TO_TESTFLIGHT.md** | This file | Meta overview & navigation |

---

## 🤔 FAQ

**Q: How long does it actually take?**
A: 1-2 hours including all manual steps. Mostly Apple Developer portal navigation.

**Q: What if I mess up the signing?**
A: Just reconfigure in Xcode. The app code is unchanged. Rebuild and upload again.

**Q: Can I test before uploading to TestFlight?**
A: Yes, but it requires more setup. For now, TestFlight is the fastest path.

**Q: What if the build fails?**
A: Check Part 9 in TESTFLIGHT_DEPLOYMENT_GUIDE.md for common fixes.

**Q: Can I distribute to external testers?**
A: Yes, after internal testing is done. Create external testing group in TestFlight.

**Q: When can we release on App Store?**
A: After TestFlight testing is successful. See TESTFLIGHT_DEPLOYMENT_GUIDE.md Part 13.

**Q: What if something goes wrong?**
A: All common issues are documented in TESTFLIGHT_DEPLOYMENT_GUIDE.md Part 9.

---

## 🎯 Your Goal (Reminder)

**Get a fully working iOS and macOS app on TestFlight so it can be downloaded by internal testers.**

You're doing this in 4 phases:
1. Apple Developer setup
2. Xcode configuration
3. Build & upload
4. Invite testers

**You can do this.** The process is straightforward, just takes following steps carefully.

---

## 📅 Deadline & Timeline

- **Now:** Code is ready
- **1-2 hours:** Can be on TestFlight
- **Day 2:** Internal testers have access
- **Day 3+:** Gather feedback & fix issues
- **Week 2:** Ready for broader release

---

## ✍️ Final Checklist Before You Start

- [ ] Read TESTFLIGHT_QUICK_START.md
- [ ] Have your Apple Developer credentials
- [ ] Have 1-2 hours of focused time
- [ ] Have access to your Mac for signing
- [ ] Have Internet connection
- [ ] Have list of internal testers' Apple IDs
- [ ] Bookmark TESTFLIGHT_DEPLOYMENT_GUIDE.md

---

## 🚀 Ready?

Open **TESTFLIGHT_QUICK_START.md** and start with **Step 1: Apple Developer Setup**.

You've got this! 💪

---

*Last updated: 2026-02-24*
*App Status: Code Ready ✅*
*Ready for: TestFlight Deployment 🚀*

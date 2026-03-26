# Deployment Documentation

This folder contains guides and instructions for deploying Todus to production, staging, and testing environments.

## 📚 Documents

### TESTFLIGHT_QUICK_START.md
⚡ **Fast-track 5-step guide** (1-2 hours) for deploying to TestFlight:
1. Apple Developer Setup
2. Xcode Configuration
3. Build Archive
4. TestFlight Setup
5. Pre-Flight Verification

**Best for**: Quick reference and rapid deployment

### TESTFLIGHT_DEPLOYMENT_GUIDE.md
📖 **Comprehensive step-by-step guide** with detailed instructions:
- Prerequisites checklist
- Bundle ID setup
- Code signing configuration
- Build configuration
- Testing checklist
- Troubleshooting guide
- Release notes template
- Verification workflow

**Best for**: First-time deployment or troubleshooting

## 🎯 Quick Reference

| Scenario | Document |
|----------|----------|
| First TestFlight? | Start with TESTFLIGHT_QUICK_START.md |
| Need details? | Read TESTFLIGHT_DEPLOYMENT_GUIDE.md |
| Troubleshooting? | See "If Something Fails" section in either guide |
| Building internally? | Follow step-by-step in deployment guide |

## 📋 Deployment Checklist

Before deploying:
- [ ] All code committed and tested
- [ ] Bundle IDs registered with Apple Developer
- [ ] Certificates and provisioning profiles created
- [ ] Xcode project signing configured
- [ ] Build succeeds locally
- [ ] Pre-flight testing passes

## ⏱️ Timeline

- **Prerequisites**: 30-60 minutes
- **Build & Upload**: 30-45 minutes
- **Processing**: 5-15 minutes
- **Total**: 1-2 hours

## 🚫 Common Mistakes

- ❌ Using "iOS App Development" certificate (use "Apple Distribution")
- ❌ Wrong bundle ID in Xcode
- ❌ Not downloading and installing provisioning profiles
- ❌ Incrementing version number instead of build number

## 📖 For More Information

- See [`../architecture/`](../architecture/) for app structure
- See [`../development/`](../development/) for build commands
- See [`../README.md`](../README.md) for complete documentation index

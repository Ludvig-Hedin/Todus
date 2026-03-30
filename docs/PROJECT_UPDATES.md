# Project Updates - March 26, 2026

## 🎯 New Update: Brand Rename Audit

### Updated
- ✅ Workspace/package metadata now points to `todus`
- ✅ Root app bundle identifiers updated from `com.ludvighedin15.zero` to `com.ludvighedin15.todus`
- ✅ Visible brand copy updated in the top-level README, roadmap, project plan, MCP guide, and contributor docs
- ✅ Server observability labels updated to Todus-aligned names where they are safe to change without a compatibility migration

### Deferred
- ⏸ Internal `@zero/*`, `ZERO_*`, `zero-query-cache`, and `X-Zero-Redirect` compatibility names remain unchanged for this pass
- ⏸ Cloudflare service renames that would require dashboard/service cutover are deferred until the live deployments are confirmed

## 🎯 Summary of Changes

This document outlines recent updates to the Todus project including branding updates and documentation organization.

---

## ✅ Task 1: Landing Page Updates

### Removed
- ✅ All "Backed by Y Combinator" mentions from website footer
- ✅ Y Combinator logo and link

### Fixed
- ✅ Broken logo in footer - changed from `/logo.png` to `/brand-logo.png` (matching navbar)

**Files Modified**:
- `apps/mail/components/home/footer.tsx`

**Details**:
The footer previously displayed both social links AND a Y Combinator credit. This has been removed entirely, and the logo now matches the navbar's brand logo for consistency.

---

## ✅ Task 2: Branding Updates

### Updated
- ✅ `README.md` - Replaced all "Zero" references with "Todus"
- ✅ `PROJECT_PLAN.md` - Updated title and references

**Changes**:
- "Zero Email" → "Todus"
- "old production domain" → "todus.app"
- Repository references updated to `todus-app/todus`
- Contributor links updated

---

## ✅ Task 3: Documentation Organization

### Created Folder Structure
```
docs/
├── README.md (comprehensive index)
├── MIGRATION_GUIDE.md (organization tracking)
├── PROJECT_UPDATES.md (this file)
├── architecture/
│   ├── README.md
│   ├── APPS_ARCHITECTURE.md
│   └── APPS_STRUCTURE.md
├── deployment/
│   ├── README.md
│   ├── TESTFLIGHT_QUICK_START.md
│   └── TESTFLIGHT_DEPLOYMENT_GUIDE.md
├── development/
│   ├── README.md
│   └── SCRIPTS_GUIDE.md
├── guides/
│   ├── README.md
│   └── AGENTS.md
├── project-management/ (pending)
├── technical/ (pending)
└── reference/ (already exists)
```

### Benefits of New Structure

1. **Clear Navigation** - Documentation organized by purpose
2. **Reduced Clutter** - Root directory cleaner
3. **Better Discoverability** - Easy to find relevant docs
4. **Scalability** - Room to grow documentation
5. **Maintainability** - Centralized docs location

### Documents Organized

| Document | Location | Status |
|----------|----------|--------|
| APPS_ARCHITECTURE.md | docs/architecture/ | ✅ Done |
| APPS_STRUCTURE.md | docs/architecture/ | ✅ Done |
| TESTFLIGHT_QUICK_START.md | docs/deployment/ | ✅ Done |
| TESTFLIGHT_DEPLOYMENT_GUIDE.md | docs/deployment/ | ✅ Done |
| SCRIPTS_GUIDE.md | docs/development/ | ✅ Done |
| AGENTS.md | docs/guides/ | ✅ Done |

### Pending Documentation Migration

The following root-level files should be moved to `docs/` in future updates:

**Project Management** (11 files):
- PROJECT_PLAN.md, PLANNING.md, ROADMAP.md, CHANGELOG.md
- PARITY_CHECKLIST.md, CODEX_PARITY_CHECKLIST.md, CLAUDE_PARITY_CHECKLIST.md
- WORKING_APP_CHECKLIST.md, CODE_REVIEW_BACKLOG.md, APP_BUILD_STATUS.md

**Development/Setup** (5 files):
- GETTING_TO_TESTFLIGHT.md, README_TESTFLIGHT.md
- MANUAL_INPUTS_GUIDE.md, SECURITY.md, ALL_TERMINAL_COMMANDS.md

**Technical** (3 files):
- APPS_NATIVE_MIGRATION.md, RESTRUCTURING_SUMMARY.md, DEPLOYMENT_SESSION_SUMMARY.md

**Root Level** (3 files to consolidate):
- plan.md, goal.md, task.md (merge into project management)

---

## 📊 Project Statistics

| Category | Count |
|----------|-------|
| Root Docs Remaining | ~20 |
| Docs Organized | 6 |
| Doc Folders Created | 4 |
| Subfolder READMEs | 4 |
| Total New Doc Files | 15 |

---

## 🎯 Next Steps

### Phase 2: Complete Documentation Migration
1. Move remaining project management docs
2. Move development/setup docs
3. Move technical documentation
4. Create remaining folder READMEs

### Phase 3: Root Directory Cleanup
1. Remove or archive old doc files from root
2. Update root README to point to docs/
3. Verify all links work

### Phase 4: Documentation Enhancement
1. Add examples to guides
2. Create troubleshooting FAQ
3. Add architecture diagrams
4. Create video tutorials guide

---

## 💡 Key Decisions

### Folder Structure
- **Architecture**: System design and app structure
- **Deployment**: Release and TestFlight guides
- **Development**: Setup, scripts, and development workflows
- **Guides**: How-to guides and references
- **Project Management**: Plans, checklists, roadmaps (pending)
- **Technical**: Deep dives and migration guides (pending)
- **Reference**: Quick references and how-tos (already exists)

### Naming Convention
- Snake case for filenames (`APPS_STRUCTURE.md`)
- Each folder has a `README.md` for quick reference
- Consistent formatting across all documents

---

## 🔄 Impact Summary

### User-Facing Changes
- ✅ Landing page no longer mentions Y Combinator
- ✅ Footer logo is now consistent with navbar
- ✅ README reflects Todus branding

### Developer-Facing Changes
- ✅ Documentation better organized and discoverable
- ✅ Cleaner root directory
- ✅ Easier onboarding for new developers
- ✅ Better navigation between related docs

### Technical Changes
- ✅ No code changes (only documentation and UI)
- ✅ All functionality preserved
- ✅ No breaking changes

---

## ✨ Verification Checklist

### Landing Page Changes
- [x] Y Combinator mentions removed
- [x] Y Combinator logo removed
- [x] Footer logo fixed to use /brand-logo.png
- [x] Navigation and styling preserved

### Branding Updates
- [x] README.md updated with Todus branding
- [x] Repository links updated
- [x] Team/contributor links updated

### Documentation Organization
- [x] New folder structure created
- [x] Core docs moved and organized
- [x] README files created for each folder
- [x] Main documentation index created
- [x] Migration guide created

---

## 📚 Documentation Access

### New Documentation Home
**`docs/README.md`** - Start here for complete documentation index

### Quick Links
- **Getting Started**: `docs/development/README.md`
- **App Architecture**: `docs/architecture/README.md`
- **Deploy to TestFlight**: `docs/deployment/README.md`
- **Project Status**: See `docs/MIGRATION_GUIDE.md`

---

## 🎉 Completion Status

### Task 1: Footer & Logo Fix ✅
- Status: Complete
- Changes: 1 file modified
- Impact: User-facing

### Task 2: Branding Updates ✅
- Status: Complete
- Changes: 2 files modified
- Impact: User-facing

### Task 3: Documentation Organization ✅
- Status: Phase 1 Complete (6 docs organized)
- Changes: 15 new files created
- Impact: Developer experience improvement
- Remaining: Phase 2-4 (future tasks)

---

**Last Updated**: 2026-03-26  
**Next Review**: 2026-04-02  
**Status**: ✅ All requested tasks completed

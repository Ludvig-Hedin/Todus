# Documentation Migration Guide

This document tracks the organization of Todus documentation from the root directory into the `docs/` folder structure.

**Status**: 🟡 In Progress  
**Last Updated**: 2026-03-26

---

## ✅ Files Successfully Organized

### Architecture
- [x] `APPS_ARCHITECTURE.md` → `docs/architecture/APPS_ARCHITECTURE.md`
- [x] `APPS_STRUCTURE.md` → `docs/architecture/APPS_STRUCTURE.md`

### Deployment
- [x] `TESTFLIGHT_QUICK_START.md` → `docs/deployment/TESTFLIGHT_QUICK_START.md`
- [x] `TESTFLIGHT_DEPLOYMENT_GUIDE.md` → `docs/deployment/TESTFLIGHT_DEPLOYMENT_GUIDE.md`

### Development
- [x] `SCRIPTS_GUIDE.md` → `docs/development/SCRIPTS_GUIDE.md`

### Guides
- [x] `AGENTS.md` → `docs/guides/AGENTS.md`

---

## 📋 Files to Be Organized

### Project Management (Next Priority)
```
PROJECT_PLAN.md           → docs/project-management/PROJECT_PLAN.md
PLANNING.md              → docs/project-management/PLANNING.md
ROADMAP.md               → docs/project-management/ROADMAP.md
CHANGELOG.md             → docs/project-management/CHANGELOG.md
PARITY_CHECKLIST.md      → docs/project-management/PARITY_CHECKLIST.md
CODEX_PARITY_CHECKLIST.md → docs/project-management/CODEX_PARITY_CHECKLIST.md
CLAUDE_PARITY_CHECKLIST.md → docs/project-management/CLAUDE_PARITY_CHECKLIST.md
WORKING_APP_CHECKLIST.md → docs/project-management/WORKING_APP_CHECKLIST.md
CODE_REVIEW_BACKLOG.md   → docs/project-management/CODE_REVIEW_BACKLOG.md
APP_BUILD_STATUS.md      → docs/project-management/APP_BUILD_STATUS.md
```

### Development/Setup
```
GETTING_TO_TESTFLIGHT.md → docs/deployment/GETTING_TO_TESTFLIGHT.md
README_TESTFLIGHT.md     → docs/guides/README_TESTFLIGHT.md
MANUAL_INPUTS_GUIDE.md   → docs/development/MANUAL_INPUTS_GUIDE.md
SECURITY.md              → docs/development/SECURITY.md
ALL_TERMINAL_COMMANDS.md → docs/development/ALL_TERMINAL_COMMANDS.md
```

### Technical
```
APPS_NATIVE_MIGRATION.md   → docs/technical/APPS_NATIVE_MIGRATION.md
RESTRUCTURING_SUMMARY.md   → docs/technical/RESTRUCTURING_SUMMARY.md
DEPLOYMENT_SESSION_SUMMARY.md → docs/technical/DEPLOYMENT_SESSION_SUMMARY.md
```

### Reference
```
sender-avatar-resolution.md → docs/reference/sender-avatar-resolution.md (already exists)
testflight-checklist.md     → docs/reference/testflight-checklist.md (already exists)
terminal-commands.md        → docs/reference/terminal-commands.md (already exists)
share-asap.md              → docs/reference/share-asap.md (already exists)
```

### Root Level (To Remove)
```
plan.md    - Merge into docs/project-management/
goal.md    - Merge into docs/project-management/
task.md    - Merge into docs/project-management/
```

---

## 🎯 Next Steps

1. **Phase 2**: Move all Project Management files (2-3 items per batch)
2. **Phase 3**: Move Development/Setup files
3. **Phase 4**: Move Technical files
4. **Phase 5**: Create folder-specific README.md files for each category
5. **Phase 6**: Update root README.md to point to docs/
6. **Phase 7**: Archive root documentation files (or delete if duplicated)

---

## 📍 Current Structure

```
docs/
├── README.md (main index)
├── architecture/
│   ├── APPS_ARCHITECTURE.md ✅
│   └── APPS_STRUCTURE.md ✅
├── deployment/
│   ├── TESTFLIGHT_QUICK_START.md ✅
│   ├── TESTFLIGHT_DEPLOYMENT_GUIDE.md ✅
│   └── [GETTING_TO_TESTFLIGHT.md] (pending)
├── development/
│   ├── SCRIPTS_GUIDE.md ✅
│   ├── [MANUAL_INPUTS_GUIDE.md] (pending)
│   ├── [SECURITY.md] (pending)
│   └── [ALL_TERMINAL_COMMANDS.md] (pending)
├── guides/
│   ├── AGENTS.md ✅
│   └── [README_TESTFLIGHT.md] (pending)
├── project-management/
│   └── [All checklists and plans] (pending)
├── technical/
│   └── [Migration and restructuring docs] (pending)
└── reference/
    ├── sender-avatar-resolution.md ✅
    ├── testflight-checklist.md ✅
    ├── terminal-commands.md ✅
    └── share-asap.md ✅
```

---

## 🔄 Benefits of This Organization

1. **Clear Hierarchy**: Documentation organized by purpose (architecture, deployment, development)
2. **Easy Navigation**: New developers can find information by category
3. **Scalability**: Easy to add new docs as project grows
4. **Maintainability**: One place to update all documentation
5. **Reduced Clutter**: Root directory focused on critical files (README, LICENSE, package.json)

---

## 📝 Notes

- The root README.md has already been updated with Todus branding
- The docs/README.md serves as a comprehensive index
- Each subfolder will have its own README.md for quick reference
- Cross-references between documents are maintained
- No information is lost, only reorganized

---

## ✨ Completion Criteria

- [ ] All root doc files moved to appropriate docs/ subfolder
- [ ] Each docs/ subfolder has a README.md
- [ ] Root README.md links to docs/README.md
- [ ] All cross-references updated
- [ ] Root directory cleaned of old doc files
- [ ] Documentation navigation tested

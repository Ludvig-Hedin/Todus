# Guides

Quick reference guides and how-to documentation for common tasks.

## 📚 Documents

### AGENTS.md
Comprehensive guide to Todus AI capabilities and agent configuration:
- Project structure overview
- Frequently used commands
- Development setup steps
- AI features and automation
- Important restrictions and best practices

**Use this**: To understand project structure and AI capabilities

## 🎯 Common Tasks

### Getting Started with Development
1. Read [`../development/`](../development/) for setup
2. Use [`AGENTS.md`](./AGENTS.md) to understand the project
3. Follow [`../deployment/`](../deployment/) for TestFlight

### Setting Up for the First Time
```bash
# 1. Install dependencies
bun install

# 2. Setup environment
bun nizzy env
bun nizzy sync

# 3. Start database and servers
bun go
```

### Working with AI Features
- Check AGENTS.md for AI capabilities
- Review `apps/server/src/lib/` for AI service implementation
- Check `apps/mail/components/ui/ai-sidebar.tsx` for UI

### Deploying to TestFlight
1. Start with [`../deployment/TESTFLIGHT_QUICK_START.md`](../deployment/TESTFLIGHT_QUICK_START.md)
2. For detailed steps, use [`../deployment/TESTFLIGHT_DEPLOYMENT_GUIDE.md`](../deployment/TESTFLIGHT_DEPLOYMENT_GUIDE.md)

## ⚡ Quick Reference

| Task | Document |
|------|----------|
| Setup development | [`../development/`](../development/) |
| Run development | [`../development/SCRIPTS_GUIDE.md`](../development/SCRIPTS_GUIDE.md) |
| Understand AI | [`AGENTS.md`](./AGENTS.md) |
| Deploy to TestFlight | [`../deployment/TESTFLIGHT_QUICK_START.md`](../deployment/TESTFLIGHT_QUICK_START.md) |
| System architecture | [`../architecture/`](../architecture/) |

## 📖 For More Information

- See [`../README.md`](../README.md) for complete documentation index
- See [`../MIGRATION_GUIDE.md`](../MIGRATION_GUIDE.md) for documentation organization

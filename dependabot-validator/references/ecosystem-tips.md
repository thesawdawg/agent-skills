# Tips for common ecosystems

## npm / Node.js
- Semver major bumps (1.x → 2.x) almost always have breaking changes.
- Check `peerDependencies` changes in the updated lib's `package.json`.
- Watch for renamed exports or CommonJS → ESM transitions.

## Python
- Check if the package dropped a Python version.
- Watch for import-path renames (`from pkg import OldClass` → `from pkg.new import OldClass`).
- Review type-annotation changes if the project uses mypy/pyright.

## Rust
- Check whether public trait implementations changed (method signatures, added required methods).
- Feature-flag changes can silently remove functionality.

## Go
- Module-path changes mean all imports must be updated.
- Interface changes break any code that implements or accepts the interface.

## Java
- Check for removed annotations or changed annotation parameters.
- Spring Boot / Jakarta EE namespace migrations are common breaking points.

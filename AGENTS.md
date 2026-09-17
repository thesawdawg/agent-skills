# Repository maintenance

Read STRUCTURE.md for bundle rules and verification. Skills live at the root;
D.A.V.E. retains its plugin-compatible nested path. Update README's catalog and
run `bash scripts/verify.sh` when changing entries. Keep required assets inside
selected bundles and declare sibling dependencies explicitly.

Preserve user edits and state. Never run git push. Use focused Conventional
Commits without co-author trailers unless requested. Do not install/update the
user's personal skills as a side effect of source changes.

Ask only for missing information that changes the result. Keep documentation
and safeguards with their owner. Existing approved plans govern scope; record
material deviations there. Use mock/loopback tests for external helpers.

# Final Cut Tools

## Product

- Make creating in Final Cut Pro feel effortless. Keep recording and editing in one workflow.
- Prefer native macOS UI and Apple's supported workflow-extension and media APIs.
- A recording must be written to the selected destination, never silently redirected to the startup disk.
- Never overwrite or remove a user's recordings. Make failures visible and preserve recoverable media.
- Verify changes inside Final Cut Pro, including a real recording and a drag onto a timeline when capture or integration changes.

## Public presentation

- Keep README.md up to date whenever features, setup, compatibility, screenshots, or limitations change.
- Make the README look and work like a professional, widely shared GitHub project: a clear benefit-led opening, useful badges, a real screenshot or short demo, an easy quick start, concise features, compatibility, troubleshooting, contribution guidance, and a license.
- Borrow the clarity and polish of successful GitHub repositories, not their hype. Do not invent adoption, stars, testimonials, benchmarks, supported platforms, or working features.
- Lead with the user's experience and the steps the tool saves. Explain implementation only where it helps installation, contribution, or understanding a real limitation.
- Keep personal names, identifying author metadata, machine-specific paths, secrets, recordings, and private settings out of the public repository. Use the project brand in public metadata.
- AGENTS.md is the source of these instructions. CLAUDE.md must remain a relative symlink to AGENTS.md.

## Development

- Each tool belongs under tools/. Shared build scripts belong under scripts/.
- Keep generated apps, SDK binaries, test recordings, local configuration, and build output out of Git.
- Build with python3 scripts/build.py. Use the official Apple Workflow Extension SDK for distribution builds; do not redistribute Apple's SDK or frameworks in the source repository.
- Document checks actually performed and any unverified behavior. Do not declare the extension ready merely because it compiles.

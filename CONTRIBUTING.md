# Contributing

Build a tool that removes a repeated step from creating in Final Cut Pro.

## Build and run

1. Read [AGENTS.md](AGENTS.md).
2. Install Xcode and select its command-line tools.
3. Install Apple's Workflow Extension SDK, or use the local development runtime in an installed Final Cut Pro.
4. Run `python3 scripts/build.py --install`.
5. Open the containing app from Applications once, then launch the recorder through Final Cut Pro's Extensions menu.

Close the recorder extension before rebuilding. A loaded extension may continue using its previous executable until it is closed and reopened.

## Verify the workflow

For changes to recording or integration, verify a real camera-and-microphone take:

- The extension opens inside Final Cut Pro.
- The camera preview and audio meter work with the selected devices.
- Record and stop a short take on the selected drive.
- Confirm the file contains playable video and audio.
- Drag the take onto an open Final Cut project timeline.
- Close and reopen the extension to check remembered settings.
- Check that an unavailable destination produces a useful error rather than silently writing elsewhere.

Do not commit test recordings, personal screenshots, SDK frameworks, build output, or local device configuration.

## Pull requests

Describe the editing problem, the resulting behavior, and the validation you actually performed. Update the README, compatibility information, and demo assets when applicable. A compilation check alone does not establish that a workflow extension works.

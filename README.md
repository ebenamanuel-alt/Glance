[README.md](https://github.com/user-attachments/files/33537081/README.md)
# Glance

Look at a screen and your cursor goes there. A Mac app that uses the head tracking in AirPods to know which screen you're looking at.

- **Cursor follows your eyes:** look at a screen and the cursor and typing move there.
- **Nod to focus:** hold Control + Option and nod to bring the window under the cursor to the front.
- **Move windows:** hold Control + Option + Command and look at another screen to move the front window there.
- **Spotlight:** screens you aren't looking at dim slightly.
- **Privacy:** look away for a while and your screens are hidden until you look back.

Everything is adjustable in the settings panel. No camera is used.

## Build

`bash app/build.sh` on a Mac with Apple's Command Line Tools, or let GitHub Actions build it (Actions tab, then download the Glance artifact).

Needs macOS 14 or later and AirPods Pro, AirPods Max or AirPods (3rd generation or later).

Made by Eben Amanuel.

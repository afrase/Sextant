# Security policy

Sextant writes firmware to a keyboard and can read its key events, so security reports matter here.

## Reporting a vulnerability

Report it privately through GitHub's private vulnerability reporting: open the repository's **Security** tab and choose **Report a vulnerability**. Please don't open a public issue, a pull request or a discussion, and don't send it by email.

Include what you found, how to reproduce it, and what an attacker gains.

## In scope

- **The flasher's guards:** anything that could make Sextant write outside the application region `[0x08002000, 0x08042000)`, send a mass erase, flash an image whose DFU suffix doesn't match the connected bootloader, skip the md5 check, or treat a failed write as success.
- **The build sandbox:** a layout or imported file that makes a firmware build reach the network, read the user's files, or write outside its build folder.
- **Raw-HID privacy:** key events that leave memory, reach a log or disk, arrive while secure input is on, or reveal more than key positions.
- **Generator injection:** layout content (names, macros, labels, settings) that ends up as unintended C code or build flags in the generated firmware source.
- **Oryx import parsing:** a crafted Oryx response or `.sextant` file that crashes Sextant, corrupts the library, or escapes its folder.

## Supported versions

Only `main` is supported. There are no releases yet.

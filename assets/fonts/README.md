# Bundled JobMate fonts

These assets supply the typography specified by the Figma handoff without runtime
font requests. Downloaded from the official Google Fonts repository on 2026-11-03:

- [Outfit](https://github.com/google/fonts/tree/main/ofl/outfit): variable font;
  registered for the UI's 300, 400, 500, 600 and 700 weights.
- [DM Serif Display](https://github.com/google/fonts/tree/main/ofl/dmserifdisplay):
  regular and italic, weight 400. Heavier requested styles may be synthesized.
- [DM Mono](https://github.com/google/fonts/tree/main/ofl/dmmono): regular 400
  and medium 500. Heavier requested styles may be synthesized.

Each family's SIL Open Font License is included alongside its font files as
`outfit-OFL.txt`, `dmserifdisplay-OFL.txt` and `dmmono-OFL.txt`. Font binaries are
unmodified; Outfit's variable font is registered at multiple weights using the
same asset. No font package or external runtime service is used.

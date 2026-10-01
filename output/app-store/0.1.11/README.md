# Heeler 0.1.11 App Store screenshot exports

These exports preserve the exact application UI from the committed iPhone
captures and add deterministic marketing copy over a generated background.

## Exports

- iphone-6.9/01-every-agent-one-console.png
  - Source: docs/images/console-iphone.png
  - Copy: “Every Agent. One Console.”
- iphone-6.9/02-type-directly-stay-in-flow.png
  - Source: docs/images/live-terminal-iphone.png
  - Copy: “Type Directly. Stay in Flow.”
- iphone-6.9/03-control-without-leaving-the-flow.png
  - Source: docs/images/agent-iphone.png
  - Copy: “Control Without Leaving the Flow”
- iphone-6.9/04-your-shell-within-reach.png
  - Source: docs/images/terminal-iphone.png
  - Copy: “Your Shell. Within Reach.”
- iphone-6.9/05-skills-without-breaking-flow.png
  - Source: docs/images/skills-iphone.png
  - Copy: “Skills Without Breaking Flow”
- iphone-6.9/06-your-agents-at-a-glance.png
  - Source: docs/images/live-activity-iphone.png
  - Copy: “Your Agents. At a Glance.”
- iphone-6.9/07-see-what-changed.png
  - Source: docs/images/changes-iphone.png
  - Copy: “See What Changed.”
- iphone-6.9/08-every-change-line-by-line.png
  - Source: docs/images/diff-iphone.png
  - Copy: “Every Change. Line by Line.”

All files are opaque 1320×2868 PNGs for the iPhone 6.9-inch App Store slot.

## Provenance

The background was generated with OpenAI image generation as an abstract,
text-free dark terminal texture. All UI, headlines, subheads, borders, masks,
and sizing are composed locally by compose_mockups.py; the source screenshots
are never redrawn by a generative model.

## Regenerate

Run from the repository root with Pillow installed:

```sh
python3 output/app-store/0.1.11/compose_mockups.py
```

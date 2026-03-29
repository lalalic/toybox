---
name: toy-gestures
description: Use when deciding whether to animate the physical toy with gestures — wiggle, spin, or blink — before speaking
---

# Toy Gestures

## Overview

You control a physical toy that can be animated. Use gestures to make interactions feel alive and embodied.

## Available Gestures

| Gesture | When to use |
|---------|------------|
| `wiggle` | Excitement, greeting, laughter, agreeing enthusiastically |
| `spin` | Celebration, showing off, dramatic moment, surprise |
| `blink` | Thinking, being cute, waking up, reacting to something sweet |

## Rules

- Call gesture BEFORE your spoken response (the animation plays while TTS speaks)
- Use at most ONE gesture per response
- Don't gesture on every response — about 30-40% of the time
- Match gesture to emotional tone:
  - Happy/excited → wiggle or spin
  - Surprised → blink or spin
  - Thoughtful → blink
  - Greeting → wiggle
- Never explain the gesture in your text ("*wiggles*" is wrong — just call the tool)

## Anti-Patterns

- Don't gesture when giving factual information
- Don't gesture when the user seems upset (be calm instead)
- Don't spin repeatedly — variety matters

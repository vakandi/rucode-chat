[<img src="https://img.shields.io/badge/App_Store-0D96F6?&logo=app-store&logoColor=white">](https://apps.apple.com/gb/app/enchanted-llm/id6474268307)
![Swift](https://img.shields.io/badge/swift-F54A2A?&logo=swift&logoColor=white)
![Release](https://img.shields.io/github/v/release/gluonfield/enchanted)
![Stars](https://img.shields.io/github/stars/gluonfield/enchanted.svg)
[<img src="https://img.shields.io/twitter/url?url=https%3A%2F%2Ftwitter.com%2Famgauge">](https://twitter.com/amgauge)
![iOS](https://img.shields.io/badge/iOS-000000?&logo=os&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-000000?style=?&logo=os&logoColor=white)
![visionOS](https://img.shields.io/badge/visionOS-000000?style=?&logo=os&logoColor=white)

# RuCode Chat

RuCode Chat is a community fork of [Enchanted](https://github.com/gluonfield/enchanted), adapted to chat with the OpenCodeRust engine through its Bun control API. The original project’s UI, license, and attribution are retained.

The client uses Bun control (`/models`, `/server/health`) and the OpenCodeRust child (`/session`, `/session/{id}/prompt`, `/event`). Bun and child URLs, token, and server-visible working directory are configured in Settings. Defaults target the local Bun server on port 5656 and child on 4096; remote devices need explicit reachable addresses and secure transport.

The upstream screenshots and UI examples below document the Enchanted components this fork retains; they are not screenshots of the current RuCode Chat integration.

## Demo

[<img src="./assets/promo.png">](https://www.youtube.com/watch?v=zW3roZ_vM5Q)

[Vision Pro Demo](https://www.youtube.com/watch?v=y4ZeGU5IdHA)

## Showcase

### Macbook

![image](https://github.com/AugustDev/enchanted/assets/5672094/32a6a203-19a2-4cc1-adc9-cfac8445dd42)

#### Dark mode

![image](https://github.com/AugustDev/enchanted/assets/5672094/6202d235-6c34-4f79-b08a-a372fca0439e)

#### Settings

<img src="https://github.com/AugustDev/enchanted/assets/5672094/b03acfc7-cbc3-4bab-92cd-73d3eb75b47e" width="1000" height="100%">

#### Completions

 <img src="https://github.com/AugustDev/enchanted/assets/5672094/5ca80a65-1bec-4d6c-8065-f0a26861c3c2" width="1000" height="100%">

#### Use from anywhere

https://github.com/AugustDev/enchanted/assets/5672094/221d2a48-9218-4579-b284-a1ad2845e4d6

#### Build custom prompt templates and use anywhere

<img width="599" alt="Xnapper-2024-05-02-18 57 19" src="https://github.com/AugustDev/enchanted/assets/5672094/7b69fe50-5399-4c0b-a269-f28353b8ca27">

https://github.com/AugustDev/enchanted/assets/5672094/8bdebd5e-2910-4855-bb10-91239cafbc28

#### Custom completion

https://github.com/AugustDev/enchanted/assets/5672094/2ef476e7-8fc5-4992-9152-6df3847056d6

### iPhone

Multimodal

<img src="https://github.com/AugustDev/enchanted/assets/5672094/f2a7dafa-9470-4689-9f5a-27b6eb0e168d" width="1000" height="100%">

Markdown

<img src="https://github.com/AugustDev/enchanted/assets/5672094/9caefcb2-69eb-46d0-8d4f-b6269d7c2937" width="1000" height="100%">

Conversation history

<img width="959" alt="Xnapper-2024-05-03-12 00 28" src="https://github.com/AugustDev/enchanted/assets/5672094/7dade8ec-e94d-4936-9237-f2f2bc1533f2">

### Vision Pro

<img width="1534" alt="image" src="https://github.com/AugustDev/enchanted/assets/5672094/810f600a-4377-48e3-9c94-7bb90b78acaf">

<img width="1496" alt="image" src="https://github.com/AugustDev/enchanted/assets/5672094/6014a0b4-03ed-4def-b26c-b9baefad3781">




- Text to Speech (Read Aloud)
- Conversation history included in the API calls
- Dark/Light mode
- Conversation history is stored on your device
- Markdown support (nicely displays tables/lists/code blocks)
- Voice prompts
- Image attachments for prompts
- Specify system prompt used for every conversations
- Edit message content or submit message with different model
- Delete single conversation / delete all conversations
- macOS Spotlight panel <kbd>Ctrl</kbd>+<kbd>⌘</kbd>+<kbd>K</kbd>
- All features work offline

## Development status

This fork is under active development. The initial chat path supports text prompts, Rust SSE text deltas, Rust session/history discovery, Bun model and Rust agent selection, and shared Bun-hosted agent photos. Robust stream reconnect/deduplication, server start/stop scripts, and image prompts are not yet complete. Existing local SwiftData conversations are preserved and are not migrated to Rust sessions.

To build, open `Enchanted.xcodeproj` in Xcode and select the Enchanted scheme. The executable’s display name is RuCode Chat. A full app build requires Xcode; command line tools alone are insufficient.

# Contact

For any questions please do not hesitate to contact me at augustinas@subj.org

# Author

Augustinas Malinauskas

# Multi-Emoji Chat Translation Design

## Goal

TypeWhale adds a stronger emoji-aware chat translation style for Chinese-to-English chat use. It keeps the existing social-window auto routing, and also gives the user a manual translation direction that forces this style in any app.

## Product Behavior

- The existing `中译英` direction remains the normal clear chat/business-friendly English path.
- Social windows such as WeChat, Messages, WhatsApp, Slack, Telegram, LINE, Signal, Threads, X/Twitter, Instagram, and Xiaohongshu keep automatic social routing.
- Social-window Chinese-to-English translation now uses a richer emoji chat prompt when the source tone is casual, warm, playful, celebratory, scheduling-oriented, or light personal chat.
- A new manual direction appears in the translation direction picker: `中译英·多表情聊天`.
- The manual mode always uses the richer emoji chat prompt, even outside the social-window list.
- English-to-Chinese translation remains unchanged and does not get an emoji/social variant.

## Emoji Rules

- Emoji are semantic and tone-supporting, like the reference image: placed near meaningful words or at natural sentence ends.
- Use 1-4 emoji only when they fit the source meaning and chat context.
- Do not add emoji for formal work, customer communication, technical debugging, private/sensitive, conflict, medical/legal/financial, or serious content.
- Do not replace information with emoji, do not add emotions the source did not imply, and do not make the output childish or noisy.

## Implementation Shape

- Extend `SmartTranslationDirection` with a `chineseToEnglishEmojiChat` case.
- Add a dedicated prompt variant in `SmartTranslationPromptStore`.
- Update `SmartTranslationPromptBuilder` so either manual emoji-chat mode or social-window auto routing uses that prompt.
- Update the translation prompt editor so users can edit/reset the new mode independently.
- Keep storage keys separate so existing custom normal/social prompts are not overwritten.

## Validation

- `SmartTranslationCheck` covers the new menu tag, display name, template storage, social auto routing, manual forced routing, and the unchanged English-to-Chinese behavior.
- Installed-app validation checks the Settings > Smart translation direction picker and a real Chinese-to-English chat translation path.

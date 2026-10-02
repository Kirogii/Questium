<!--
Curated release notes for the NEXT version. Append user-facing bullets here as
work lands, grouped under the headings below, then bump versionName and push.
CI renders this into the release body, and `--cut` archives it into
CHANGELOG.md and clears it after the release.

Write for someone deciding whether to update: what changed for them, not which
files moved. See .github/scripts/release_notes.py.
-->

### New

### Improve
- On-device text recognition can now use PaddleOCR v5 instead of the built-in model. It is about a third of the size — 16.6 MB rather than 43.6 MB — which is the trade: measured on a test page, it reads hand-lettered Japanese less accurately than the built-in model, so it is offered as a space saving rather than an upgrade, and the built-in model stays the default
- Cloud Gemini translations now ask for a structured JSON reply matched to the input lines, so the translation no longer depends on the model returning a recognisable list format. A line that cannot be translated for content reasons is replaced on its own instead of causing the whole page to fail
- The reader's translation indicator now names the stage a page is actually in — detecting, translating, inpainting, or typesetting — instead of guessing from the page count, and pages that could not be translated now say why rather than only that they were skipped

### Fix
- Fix all translations on a page disappearing when one text region was too short. A short line of translated text - a sound effect, a single character - made the image service throw while drawing, which discarded every other translation on that page
- Fix a crash when the on-device model failed to swap over. Unloading the previous model while loading a new one was not guarded like every other unload, so a failure there could escape the local translation path instead of falling back like other local model errors do
- Fix a failed model import being able to block all future model imports. An interrupted copy of a GGUF file could leave a partial file behind that the model list never showed, while it still counted against the storage needed to import anything else
- Fix translated text disappearing from pages sent to the image translation service. When a single word was too wide to fit a line, the wrapping code replaced the line it had just finished instead of starting a new one, so everything before that word was dropped from the page
- Fix AI translation quietly giving up on a page. When the on-device Gemini model returned nothing and offline fallback was turned off, the untranslated page was displayed and counted as done instead of being marked as failed, so it could never be retried. A provider that crashed also reported itself as an un-downloaded model, sending you to download something you already had. Pages that are too large or malformed to process now say so plainly
- Fix a page being dropped at the moment it is submitted for AI translation, which could happen when a chapter was translating faster than it was being read. A page rejected for being unreadable no longer leaves a stalled entry behind that held up the rest of the chapter
- Fix translated title and description being cached against the wrong provider when Gemini Nano was in use, so they were thrown away and re-translated on every visit
- Fix scrolling stuttering in the strip and continuous readers, especially on long manhwa pages. Every page shown was being read into memory twice over - once on the main thread, which could visibly stall the scroll - even though the only features that need a page in memory are off by default
- Fix a wide page's first half disappearing behind the page before it when rotating the device with Split wide pages on, so the two halves could not be tapped through in order
- Fix browsing E-Hentai getting steadily slower the longer you browsed. With detailed logging enabled the background log writer could stop and never restart, after which every log line piled up in a queue nothing was emptying

# tts_kokoro

Crystal shard client for `kokoro_api_server`. Stateful sentence tokenization and stream buffering.

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  tts_kokoro:
    github: user/tts_kokoro
```

## Usage

```crystal
require "tts_kokoro"

# 1. Initialize client (uses keep-alive automatically)
tts = TtsKokoro::TTS.new(endpoint: "http://127.0.0.1:8888/speak")

# 2. Synchronous block speak
tts.speak_blocking("Hello world!")

# 3. Streaming buffer integration
buffer = TtsKokoro::StreamingTTSBuffer.new(tts, voice_blend: "af_bella", speed: 1.0)
buffer.start

# Push streaming chunks from LLM
buffer.push("This is a ")
buffer.push("sentence. Next ")
buffer.push("sentence starts here.")

# Flush when LLM finishes
buffer.flush
```

## Features

* Stateful `SentenceTokenizer` skips splits on decimals (`v1.0`), initials (`U.S.`), lists (`1. Item`), and multiple punctuation (`Wait!!!`).
* Connection health recovery loop with exponential backoff.
* Background fiber exception safety routing to Crystal standard `Log`.

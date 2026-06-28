require "./spec_helper"

class MockTTS < TtsKokoro::TTS
  getter speak_calls = [] of String
  getter? stop_called = false

  def initialize
    # Pass dummy endpoint
    super("http://127.0.0.1:9999/speak")
  end

  # Override speak_blocking to collect calls and simulate playback latency
  def speak_blocking(text : String, voice : String | Hash(String, Float64) = "af_bella", speed = 1.0)
    @speak_calls << text
    sleep 0.05.seconds # short sleep to allow testing concurrent cancellation
  end

  # Override stop to record that it was called
  def stop
    @stop_called = true
  end
end

describe TtsKokoro::SentenceTokenizer do
  it "splits simple sentences" do
    tokenizer = TtsKokoro::SentenceTokenizer.new
    tokenizer.push("Hello! ").should eq(["Hello!"])
    tokenizer.push("This is a test. ").should eq(["This is a test."])
  end

  it "skips code blocks" do
    tokenizer = TtsKokoro::SentenceTokenizer.new
    tokenizer.push("Here is code: ").should eq([] of String)
    tokenizer.push("```crystal\nputs 123.\n```\n").should eq(["Here is code:"])
    tokenizer.push("Done. ").should eq(["Done."])
  end

  it "skips inline code" do
    tokenizer = TtsKokoro::SentenceTokenizer.new
    tokenizer.push("Use `sys.exit(0)` to exit. ").should eq(["Use `sys.exit(0)` to exit."])
  end

  it "handles multiple punctuation marks" do
    tokenizer = TtsKokoro::SentenceTokenizer.new
    tokenizer.push("Wait!!! ").should eq(["Wait!!!"])
    tokenizer.push("Are you sure?! ").should eq(["Are you sure?!"])
  end

  it "excludes numbered lists at start of line/buffer" do
    tokenizer = TtsKokoro::SentenceTokenizer.new
    tokenizer.push("1. First item. ").should eq(["1. First item."])
    tokenizer.push("\n2. Second item. ").should eq(["2. Second item."])
  end

  it "splits on numbers at the end of sentences" do
    tokenizer = TtsKokoro::SentenceTokenizer.new
    tokenizer.push("The year is 2026. Next line. ").should eq(["The year is 2026.", "Next line."])
  end

  it "excludes initials and acronyms" do
    tokenizer = TtsKokoro::SentenceTokenizer.new
    tokenizer.push("U.S. government is big. ").should eq(["U.S. government is big."])
  end

  it "handles flush to emit remaining buffers" do
    tokenizer = TtsKokoro::SentenceTokenizer.new
    tokenizer.push("Incomplete sentence")
    tokenizer.flush.should eq(["Incomplete sentence"])
  end
end

describe TtsKokoro::StreamingTTSBuffer do
  it "buffers and sends complete sentences sequentially" do
    mock_tts = MockTTS.new
    buffer = TtsKokoro::StreamingTTSBuffer.new(mock_tts)
    buffer.start

    buffer.push("Hello! ")
    buffer.push("This is a test. ")
    buffer.push("We are streaming now. ")
    buffer.flush

    # Wait a bit for the worker fiber to process the sentences
    sleep 0.2.seconds

    mock_tts.speak_calls.should eq([
      "Hello!",
      "This is a test.",
      "We are streaming now."
    ])
  end

  it "stops queue processing and calls stop on TTS when cancelled" do
    mock_tts = MockTTS.new
    buffer = TtsKokoro::StreamingTTSBuffer.new(mock_tts)
    buffer.start

    # Push sentences
    buffer.push("Sentence one. ")
    buffer.push("Sentence two. ")
    buffer.push("Sentence three. ")
    buffer.push("Sentence four. ")

    # Let the first sentence start speaking
    sleep 0.01.seconds

    # Cancel the buffer
    buffer.cancel

    # Let some time pass to see if other sentences are skipped
    sleep 0.2.seconds

    mock_tts.speak_calls.should_not contain("Sentence two.")
    mock_tts.speak_calls.should_not contain("Sentence three.")
    mock_tts.speak_calls.should_not contain("Sentence four.")
    
    mock_tts.stop_called?.should be_true
  end
end

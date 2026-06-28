require "./spec_helper"

describe TtsKokoro::TTS do
  describe ".sanitize_for_speech" do
    it "removes content within square brackets" do
      result = TtsKokoro::TTS.sanitize_for_speech("Hello [STATUS: OK] world!")
      result.should eq("Hello world!")
    end

    it "removes LaTeX-style notation" do
      result = TtsKokoro::TTS.sanitize_for_speech("The answer is $x^2 + y^2 = z^2$ yes.")
      result.should eq("The answer is yes.")
    end

    it "removes markdown bold" do
      result = TtsKokoro::TTS.sanitize_for_speech("This is **very** important.")
      result.should eq("This is very important.")
    end

    it "removes markdown italic" do
      result = TtsKokoro::TTS.sanitize_for_speech("This is *very* important.")
      result.should eq("This is very important.")

      result2 = TtsKokoro::TTS.sanitize_for_speech("This is _very_ important.")
      result2.should eq("This is very important.")
    end

    it "removes any remaining standalone asterisks" do
      result = TtsKokoro::TTS.sanitize_for_speech("Look at these *** stars.")
      result.should eq("Look at these stars.")
    end

    it "removes emojis" do
      result = TtsKokoro::TTS.sanitize_for_speech("Hello 🌍! I am happy 😀.")
      result.should eq("Hello! I am happy.")
    end

    it "normalizes whitespace around punctuation" do
      result = TtsKokoro::TTS.sanitize_for_speech("Wait  ,  what ?   Yes . ")
      result.should eq("Wait, what? Yes.")
    end
  end
end

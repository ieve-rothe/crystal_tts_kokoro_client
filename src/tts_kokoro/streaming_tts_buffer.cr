module TtsKokoro
  # Buffers streaming LLM response chunks, extracts complete sentences using 
  # SentenceTokenizer, and feeds them sequentially to the TTS client.
  class StreamingTTSBuffer
    @tokenizer : SentenceTokenizer
    @tts_channel : Channel(String?)?
    @tts : TTS
    @voice_blend : Hash(String, Float64) | String
    @speed : Float64
    @cancelled : Bool
    property on_complete : Proc(Nil)?

    def initialize(@tts : TTS, @voice_blend : Hash(String, Float64) | String = "af_bella", @speed : Float64 = 1.0)
      @tokenizer = SentenceTokenizer.new
      @tts_channel = nil
      @cancelled = false
      @on_complete = nil
    end

    # Returns true if this buffer has been cancelled.
    def cancelled? : Bool
      @cancelled
    end

    # Starts the background TTS worker fiber.
    def start
      channel = Channel(String?).new(100) # Buffer to prevent blocking main thread
      @tts_channel = channel

      spawn do
        begin
          loop do
            break if @cancelled
            sentence = channel.receive
            break if sentence.nil? # Exit when we receive termination signal
            break if @cancelled

            # Speak each sentence sequentially (blocking)
            @tts.speak_blocking(
              text: sentence,
              voice: @voice_blend,
              speed: @speed
            )

            break if @cancelled
          end
        rescue ex : Channel::ClosedError
          # Channel was closed, exit gracefully
        rescue ex
          TTS::Log.error { "TTS buffer fiber crashed: #{ex.message}" }
        ensure
          @on_complete.try(&.call)
        end
      end
    end

    # Cancels the buffer's execution and aborts active TTS playback.
    def cancel
      @cancelled = true
      @tts_channel.try(&.close)
      @tts.stop
    end

    # Push a streaming chunk into the buffer.
    def push(chunk : String)
      return if @cancelled
      return unless tts_channel = @tts_channel

      sentences = @tokenizer.push(chunk)
      sentences.each do |sentence|
        send_sentence(tts_channel, sentence)
      end
    end

    # Flush any remaining text in buffer.
    def flush
      return if @cancelled
      return unless tts_channel = @tts_channel

      sentences = @tokenizer.flush
      sentences.each do |sentence|
        send_sentence(tts_channel, sentence)
      end

      # Signal end of stream
      begin
        tts_channel.send(nil)
      rescue ex : Channel::ClosedError
        # Channel was closed during cancel, ignore
      end
    end

    private def send_sentence(channel : Channel(String?), sentence : String)
      return if sentence.empty? || @cancelled
      
      begin
        # Blocking send propagates backpressure up to main thread if queue fills up
        channel.send(sentence)
      rescue ex : Channel::ClosedError
        # Channel was closed during cancel, ignore
      end
    end
  end
end

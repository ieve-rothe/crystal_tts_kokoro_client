require "http/client"
require "json"
require "log"

module TtsKokoro
  # HTTP client for text-to-speech synthesis with keep-alive pooling, 
  # robust connection diagnostics, and health recovery probes.
  class TTS
    Log = ::Log.for("tts_kokoro")

    @endpoint : String
    @client : HTTP::Client
    @server_online = true
    @probing = false

    def initialize(
      @endpoint = "http://127.0.0.1:8888/speak",
      connect_timeout : Time::Span = 2.seconds,
      read_timeout : Time::Span = 30.seconds
    )
      uri = URI.parse(endpoint)
      @client = HTTP::Client.new(uri.host.not_nil!, uri.port.not_nil!, tls: uri.scheme == "https")
      @client.connect_timeout = connect_timeout
      @client.read_timeout = read_timeout
    end

    # Sanitizes text for natural speech output by removing formatting and symbols.
    def self.sanitize_for_speech(text : String) : String
      cleaned = text
      cleaned = cleaned.gsub(/\bvs\./i, "versus")
      cleaned = cleaned.gsub(/\[[^\]]*\]/, "")
      cleaned = cleaned.gsub(/\$[^$]*\$/, "")
      cleaned = cleaned.gsub(/\*\*([^*]+)\*\*/, "\\1")
      cleaned = cleaned.gsub(/\*([^*]+)\*/, "\\1")
      cleaned = cleaned.gsub(/_([^_]+)_/, "\\1")
      cleaned = cleaned.gsub(/\*+/, "")
      
      cleaned = String.build(cleaned.bytesize) do |io|
        cleaned.each_char do |char|
          codepoint = char.ord
          unless (codepoint >= 0x1F300 && codepoint <= 0x1F9FF) ||
                 (codepoint >= 0x1F000 && codepoint <= 0x1F02F) ||
                 (codepoint >= 0x1F0A0 && codepoint <= 0x1F0FF) ||
                 (codepoint >= 0x2600 && codepoint <= 0x26FF) ||
                 (codepoint >= 0x2700 && codepoint <= 0x27BF) ||
                 (codepoint >= 0x1F600 && codepoint <= 0x1F64F) ||
                 (codepoint >= 0x1F680 && codepoint <= 0x1F6FF) ||
                 (codepoint >= 0x1F900 && codepoint <= 0x1F9FF) ||
                 (codepoint >= 0x2300 && codepoint <= 0x23FF) ||
                 (codepoint >= 0x2B50 && codepoint <= 0x2B55) ||
                 (codepoint >= 0x200D && codepoint <= 0x200D) ||
                 (codepoint >= 0xFE00 && codepoint <= 0xFE0F) ||
                 (codepoint >= 0xE0020 && codepoint <= 0xE007F)
            io << char
          end
        end
      end

      cleaned = cleaned.gsub(/\s+/, " ")
      cleaned = cleaned.gsub(/\s+([.,!?;:])/, "\\1")
      cleaned = cleaned.gsub(/([.,!?;:])\s*([.,!?;:])/, "\\1\\2")
      cleaned.strip
    end

    # Speaks text asynchronously (non-blocking) in a background fiber.
    def speak(text : String, voice : String | Hash(String, Float64) = "af_bella", speed = 1.0)
      return unless @server_online

      sanitized = TTS.sanitize_for_speech(text)
      return if sanitized.empty?

      payload = {
        "text"  => sanitized,
        "voice" => voice,
        "speed" => speed,
      }.to_json

      # Fiber execution with robust error routing
      spawn do
        begin
          response = @client.post(
            "/speak",
            headers: HTTP::Headers{"Content-Type" => "application/json"},
            body: payload
          )

          unless response.status.success?
            Log.error { "TTS Server Error: #{response.body}" }
          end
        rescue ex
          handle_connection_failure(ex)
        end
      end
    end

    # Speaks text synchronously (blocking).
    def speak_blocking(text : String, voice : String | Hash(String, Float64) = "af_bella", speed = 1.0)
      return unless @server_online

      sanitized = TTS.sanitize_for_speech(text)
      return if sanitized.empty?

      payload = {
        "text"  => sanitized,
        "voice" => voice,
        "speed" => speed,
      }.to_json

      begin
        response = @client.post(
          "/speak",
          headers: HTTP::Headers{"Content-Type" => "application/json"},
          body: payload
        )

        unless response.status.success?
          Log.error { "TTS Server Error: #{response.body}" }
        end
      rescue ex
        handle_connection_failure(ex)
      end
    end

    # Sends a stop command to terminate active playback.
    def stop
      return unless @server_online

      begin
        response = @client.post("/stop")
        unless response.status.success?
          Log.error { "TTS Stop Error: #{response.body}" }
        end
      rescue ex
        Log.warn { "Could not connect to TTS Server for stop request: #{ex.message}" }
      end
    end

    # Closes the HTTP client.
    def close
      @client.close
    end

    # Exposes health state of backend
    def server_online? : Bool
      @server_online
    end

    private def handle_connection_failure(ex : Exception)
      Log.error { "Could not connect to TTS Server: #{ex.message}" }
      return unless @server_online

      @server_online = false
      Log.warn { "TTS has been temporarily disabled. Starting health recovery probes..." }
      start_health_probes
    end

    private def start_health_probes
      return if @probing
      @probing = true

      spawn do
        delay = 1.seconds
        loop do
          sleep delay
          begin
            # Use separate connections for health check probes to prevent connection lockups
            uri = URI.parse(@endpoint)
            probing_client = HTTP::Client.new(uri.host.not_nil!, uri.port.not_nil!, tls: uri.scheme == "https")
            probing_client.connect_timeout = 1.seconds
            probing_client.read_timeout = 1.seconds
            
            response = probing_client.get("/health")
            probing_client.close

            if response.status.success?
              @server_online = true
              @probing = false
              Log.info { "TTS Server connection re-established. TTS is re-enabled." }
              break
            end
          rescue
            # Health check failed, double backoff up to 10 seconds max
            delay = {delay * 2, 10.seconds}.min
          end
        end
      end
    end
  end
end

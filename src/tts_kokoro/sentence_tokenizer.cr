module TtsKokoro
  # Stateful sentence segmenter that splits stream chunks on sentence boundaries
  # while ignoring abbreviations, decimals, markdown formatting, and initials.
  class SentenceTokenizer
    @buffer = ""
    @in_code_block = false
    @in_inline_code = false
    @in_brackets = 0

    # User-configurable abbreviation list to preserve prosody
    property abbreviations : Set(String) = Set.new([
      "dr", "mr", "mrs", "ms", "eg", "ie", "vs", "ca", "approx",
      "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "oct",
      "nov", "dec", "st", "co", "corp", "inc", "ltd", "v", "jr", "sr",
      "am", "pm"
    ])

    def push(chunk : String) : Array(String)
      @buffer += chunk
      sentences = [] of String
      
      while !@buffer.empty?
        if @in_code_block
          # Look for closing code block
          if idx = @buffer.index("```")
            # Discard everything in the code block, including the closing backticks
            @buffer = @buffer[(idx + 3)..-1]
            @in_code_block = false
          else
            # Closing backticks not found yet, discard current buffer (it's all code)
            @buffer = ""
            break
          end
        else
          # Look for either start of a code block or the next sentence boundary
          code_block_idx = @buffer.index("```")
          boundary_idx = find_next_boundary

          if code_block_idx && (!boundary_idx || code_block_idx < boundary_idx)
            # Start of code block comes first. Treat it as an implicit sentence boundary
            pre_code_text = @buffer[0...code_block_idx].strip
            @buffer = @buffer[(code_block_idx + 3)..-1]
            @in_code_block = true
            
            unless pre_code_text.empty?
              sentences << pre_code_text
            end
          elsif boundary_idx
            # Sentence boundary comes first
            sentence = @buffer[0..boundary_idx].strip
            @buffer = @buffer[(boundary_idx + 1)..-1]
            sentences << sentence unless sentence.empty?
          else
            # No boundary or code block found, keep buffering
            break
          end
        end
      end

      sentences
    end

    def flush : Array(String)
      remaining = @buffer.strip
      @buffer = ""
      (remaining.empty? || @in_code_block) ? [] of String : [remaining]
    end

    private def find_next_boundary : Int32?
      i = 0
      while i < @buffer.size
        # Inline code boundaries
        if @buffer[i] == '`'
          @in_inline_code = !@in_inline_code
          i += 1
          next
        end
        next i += 1 if @in_inline_code

        # Brackets / Parentheses
        char = @buffer[i]
        if char == '[' || char == '('
          @in_brackets += 1
        elsif char == ']' || char == ')'
          @in_brackets = {@in_brackets - 1, 0}.max
        end

        # Sentence-ending boundaries outside formatting blocks
        if (char == '.' || char == '!' || char == '?') && @in_brackets == 0
          if is_valid_boundary?(i)
            if end_idx = find_boundary_end(i)
              return end_idx
            end
          end
        end
        i += 1
      end
      nil
    end

    private def is_valid_boundary?(index : Int32) : Bool
      char = @buffer[index]
      return true if char == '!' || char == '?'

      # Exclude ellipses
      return false if index > 0 && @buffer[index-1] == '.'
      return false if index + 1 < @buffer.size && @buffer[index+1] == '.'

      # Exclude decimals
      if index > 0 && index + 1 < @buffer.size
        return false if @buffer[index-1].ascii_number? && @buffer[index+1].ascii_number?
      end

      # Extract the preceding word and its start index
      word, word_start = extract_preceding_word(index)
      return false if word.empty?

      # Exclude abbreviations
      return false if abbreviations.includes?(word.downcase)

      # Exclude numbered lists (preceding word is numeric AND is at the start of a line/buffer)
      return false if is_numbered_list?(word, word_start)

      # Exclude initials/acronyms (preceding word is a single character)
      return false if word.size == 1

      true
    end

    private def extract_preceding_word(index : Int32) : Tuple(String, Int32)
      start_idx = index - 1
      while start_idx >= 0 && @buffer[start_idx].ascii_whitespace?
        start_idx -= 1
      end
      end_idx = start_idx
      while start_idx >= 0 && !@buffer[start_idx].ascii_whitespace? && @buffer[start_idx].ascii_alphanumeric?
        start_idx -= 1
      end
      return {"", -1} if end_idx < 0
      word_start = start_idx + 1
      { @buffer[word_start..end_idx], word_start }
    end

    private def is_numbered_list?(word : String, word_start_index : Int32) : Bool
      return false unless word.to_i?
      
      # Word is at the absolute start of the sentence buffer
      return true if word_start_index == 0
      
      # Check if the word is preceded immediately by a newline (ignoring whitespace)
      idx = word_start_index - 1
      while idx >= 0 && @buffer[idx].ascii_whitespace?
        return true if @buffer[idx] == '\n'
        idx -= 1
      end
      
      # Preceded by start of string
      idx < 0
    end

    private def find_boundary_end(index : Int32) : Int32?
      i = index + 1
      while i < @buffer.size
        char = @buffer[i]
        # Include trailing quotes, brackets, and multiple punctuation marks (!, ?, .)
        if char == '"' || char == '\'' || char == ')' || char == ']' || char == '.' || char == '!' || char == '?'
          i += 1
        elsif char.ascii_whitespace?
          return i
        else
          return nil # Mid-word punctuation (not a sentence end)
        end
      end
      nil
    end
  end
end

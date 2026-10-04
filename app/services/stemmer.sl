# Search text for the SoliDB fulltext index: lowercase word tokens. The reference tokenizes
# with FTS5 porter, which also stems; this matches whole words only.
class Stemmer
  static def tokens(text)
    Regex.find_all("[\\p{L}\\p{N}_]+", (text ?? "").downcase).map { |m| m["match"] }
  end

  static def index_text(text)
    Stemmer.tokens(text).join(" ")
  end

  static def query_terms(query)
    Stemmer.tokens(query).uniq
  end
end

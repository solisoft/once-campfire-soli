# The words of a search, lowercase, as SearchesController#query keeps them (word characters
# only). FTS5's porter tokenizer stems them, and the index, itself.
class Stemmer
  static def tokens(text)
    Regex.find_all("[\\p{L}\\p{N}_]+", (text ?? "").downcase).map { |m| m["match"] }
  end

  static def query_terms(query)
    Stemmer.tokens(query).uniq
  end
end

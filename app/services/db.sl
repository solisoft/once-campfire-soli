# Results of @sdbql blocks. A failed query comes back as an "Error: …" string rather than
# raising; these turn it into an empty result and say so in the log.
class Db
  static def array(rows)
    return rows if rows.is_a?("array")

    print("[sdbql] " + str(rows))
    []
  end

  static def first(rows)
    found = Db.array(rows)
    found.length > 0 ? found[0] : nil
  end
end

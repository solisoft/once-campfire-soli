# Integer keys. The frontend parseInt()s user and room ids (initializers/current.js), so
# keys are numbers: the creation time in microseconds, which also sorts like Rails' ids.
# They stay below 2^53, the largest integer JavaScript holds exactly.
class Ids
  static def generate
    str(int(DateTime.microtime()))
  end

  # The row inserted under a generated key, retried if another write took the same
  # microsecond. Any other failure (a taken email address) raises.
  static def create(table, attrs)
    taken = "UNIQUE constraint failed: " + table + "._key"
    for attempt in 0..5
      attrs["_key"] = Ids.generate
      try
        return Db.insert(table, attrs)
      catch error
        throw error unless str(error).contains(taken) && attempt < 4
      end
    end
    attrs
  end
end

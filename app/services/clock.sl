# Times are stored as epoch milliseconds, the precision the frontend sorts and refreshes by
# (Time::DATE_FORMATS[:epoch] in the reference).
class Clock
  static def now
    int(DateTime.microtime() / 1000)
  end

  # Time#iso8601 of a UTC time, as the views print it: 2026-02-28T19:12:00Z
  static def iso8601_z(ms)
    DateTime.from_unix(ms / 1000).utc().to_iso().replace("+00:00", "Z")
  end

  static def iso8601(ms)
    DateTime.from_unix(ms / 1000).to_iso()
  end
end

# Times are stored as epoch milliseconds, the precision the frontend sorts and refreshes by
# (Time::DATE_FORMATS[:epoch] in the reference).
class Clock
  static def now
    int(DateTime.microtime() / 1000)
  end

  static def iso8601(ms)
    DateTime.from_unix(ms / 1000).to_iso()
  end
end

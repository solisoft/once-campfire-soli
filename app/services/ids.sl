# Integer keys. The frontend parseInt()s user and room ids (initializers/current.js), so
# keys are numbers: the creation time in microseconds, which also sorts like Rails' ids.
# They stay below 2^53, the largest integer JavaScript holds exactly.
class Ids
  static def generate
    str(int(DateTime.microtime()))
  end

  # Model.create under a generated key, retried if another write took the same microsecond.
  static def create(model, attrs)
    record = nil
    for attempt in 0..5
      record = model.create(attrs, {"key": Ids.generate})
      return record if record._errors.nil? || record._errors.length == 0
    end
    record
  end
end

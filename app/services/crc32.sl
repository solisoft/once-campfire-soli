# Zlib.crc32 over a string's bytes. Soli has no bitwise operators, so XOR is arithmetic on
# the bits.
class Crc32
  static def of(text)
    crc = 4294967295
    for byte in text.bytes()
      crc = Crc32.xor(crc, byte)
      for i in 0..8
        crc = crc % 2 == 1 ? Crc32.xor(crc / 2, 3988292384) : crc / 2
      end
    end
    Crc32.xor(crc, 4294967295)
  end

  static def xor(a, b)
    result = 0
    bit = 1
    while a > 0 || b > 0
      result += bit if a % 2 != b % 2
      a = a / 2
      b = b / 2
      bit = bit * 2
    end
    result
  end
end

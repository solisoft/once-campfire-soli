# RQRCode::QRCode.new(text) (rqrcode_core 2.1) and its as_svg(viewbox: true, fill: :white,
# color: :black). Byte mode, error correction level H (rqrcode's default), the smallest version
# that fits, and the mask rqrcode picks by its own lost-point rules, so the modules match its
# output. Soli has no bitwise operators: XOR goes through a nibble table, bits through POW2.
class QrCode
  static EXP: Array = [
    1, 2, 4, 8, 16, 32, 64, 128, 29, 58, 116, 232, 205, 135, 19, 38, 76, 152,
    45, 90, 180, 117, 234, 201, 143, 3, 6, 12, 24, 48, 96, 192, 157, 39, 78, 156,
    37, 74, 148, 53, 106, 212, 181, 119, 238, 193, 159, 35, 70, 140, 5, 10, 20, 40,
    80, 160, 93, 186, 105, 210, 185, 111, 222, 161, 95, 190, 97, 194, 153, 47, 94, 188,
    101, 202, 137, 15, 30, 60, 120, 240, 253, 231, 211, 187, 107, 214, 177, 127, 254, 225,
    223, 163, 91, 182, 113, 226, 217, 175, 67, 134, 17, 34, 68, 136, 13, 26, 52, 104,
    208, 189, 103, 206, 129, 31, 62, 124, 248, 237, 199, 147, 59, 118, 236, 197, 151, 51,
    102, 204, 133, 23, 46, 92, 184, 109, 218, 169, 79, 158, 33, 66, 132, 21, 42, 84,
    168, 77, 154, 41, 82, 164, 85, 170, 73, 146, 57, 114, 228, 213, 183, 115, 230, 209,
    191, 99, 198, 145, 63, 126, 252, 229, 215, 179, 123, 246, 241, 255, 227, 219, 171, 75,
    150, 49, 98, 196, 149, 55, 110, 220, 165, 87, 174, 65, 130, 25, 50, 100, 200, 141,
    7, 14, 28, 56, 112, 224, 221, 167, 83, 166, 81, 162, 89, 178, 121, 242, 249, 239,
    195, 155, 43, 86, 172, 69, 138, 9, 18, 36, 72, 144, 61, 122, 244, 245, 247, 243,
    251, 235, 203, 139, 11, 22, 44, 88, 176, 125, 250, 233, 207, 131, 27, 54, 108, 216,
    173, 71, 142, 1
  ]
  static LOG: Array = [
    0, 0, 1, 25, 2, 50, 26, 198, 3, 223, 51, 238, 27, 104, 199, 75, 4, 100,
    224, 14, 52, 141, 239, 129, 28, 193, 105, 248, 200, 8, 76, 113, 5, 138, 101, 47,
    225, 36, 15, 33, 53, 147, 142, 218, 240, 18, 130, 69, 29, 181, 194, 125, 106, 39,
    249, 185, 201, 154, 9, 120, 77, 228, 114, 166, 6, 191, 139, 98, 102, 221, 48, 253,
    226, 152, 37, 179, 16, 145, 34, 136, 54, 208, 148, 206, 143, 150, 219, 189, 241, 210,
    19, 92, 131, 56, 70, 64, 30, 66, 182, 163, 195, 72, 126, 110, 107, 58, 40, 84,
    250, 133, 186, 61, 202, 94, 155, 159, 10, 21, 121, 43, 78, 212, 229, 172, 115, 243,
    167, 87, 7, 112, 192, 247, 140, 128, 99, 13, 103, 74, 222, 237, 49, 197, 254, 24,
    227, 165, 153, 119, 38, 184, 180, 124, 17, 68, 146, 217, 35, 32, 137, 46, 55, 63,
    209, 91, 149, 188, 207, 205, 144, 135, 151, 178, 220, 252, 190, 97, 242, 86, 211, 171,
    20, 42, 93, 158, 132, 60, 57, 83, 71, 109, 65, 162, 31, 45, 67, 216, 183, 123,
    164, 118, 196, 23, 73, 236, 127, 12, 111, 246, 108, 161, 59, 82, 41, 157, 85, 170,
    251, 96, 134, 177, 187, 204, 62, 90, 203, 89, 95, 176, 156, 169, 160, 81, 11, 245,
    22, 235, 122, 117, 44, 215, 79, 174, 213, 233, 230, 231, 173, 232, 116, 214, 244, 234,
    168, 80, 88, 175
  ]
  static XOR16: Array = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14,
    2, 3, 0, 1, 6, 7, 4, 5, 10, 11, 8, 9, 14, 15, 12, 13,
    3, 2, 1, 0, 7, 6, 5, 4, 11, 10, 9, 8, 15, 14, 13, 12,
    4, 5, 6, 7, 0, 1, 2, 3, 12, 13, 14, 15, 8, 9, 10, 11,
    5, 4, 7, 6, 1, 0, 3, 2, 13, 12, 15, 14, 9, 8, 11, 10,
    6, 7, 4, 5, 2, 3, 0, 1, 14, 15, 12, 13, 10, 11, 8, 9,
    7, 6, 5, 4, 3, 2, 1, 0, 15, 14, 13, 12, 11, 10, 9, 8,
    8, 9, 10, 11, 12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 7,
    9, 8, 11, 10, 13, 12, 15, 14, 1, 0, 3, 2, 5, 4, 7, 6,
    10, 11, 8, 9, 14, 15, 12, 13, 2, 3, 0, 1, 6, 7, 4, 5,
    11, 10, 9, 8, 15, 14, 13, 12, 3, 2, 1, 0, 7, 6, 5, 4,
    12, 13, 14, 15, 8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3,
    13, 12, 15, 14, 9, 8, 11, 10, 5, 4, 7, 6, 1, 0, 3, 2,
    14, 15, 12, 13, 10, 11, 8, 9, 6, 7, 4, 5, 2, 3, 0, 1,
    15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0
  ]
  static POW2: Array = [
    1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072, 262144
  ]
  static FORMAT_H: Array = [
    5769, 5054, 7399, 6608, 1890, 597, 3340, 2107
  ]
  static VERSION_BITS: Array = [
    0, 0, 0, 0, 0, 0, 0, 31892, 34236, 39577,
    42195, 48118, 51042, 55367, 58893, 63784, 68472, 70749, 76311, 79154,
    84390, 87683, 92361, 96236, 102084, 102881, 110507, 110734, 117786, 119615,
    126325, 127568, 133589, 136944, 141498, 145311, 150283, 152622, 158308, 161089,
    167017
  ]
  static MAX_BITS_H: Array = [
    72, 128, 208, 288, 368, 480, 528, 688, 800, 976, 1120, 1264, 1440, 1576,
    1784, 2024, 2264, 2504, 2728, 3080, 3248, 3536, 3712, 4112, 4304, 4768, 5024, 5288,
    5608, 5960, 6344, 6760, 7208, 7688, 7888, 8432, 8768, 9136, 9776, 10208
  ]
  static RS_BLOCKS_H: Array = [
    [1, 26, 9], [1, 44, 16], [2, 35, 13], [4, 25, 9],
    [2, 33, 11, 2, 34, 12], [4, 43, 15], [4, 39, 13, 1, 40, 14], [4, 40, 14, 2, 41, 15],
    [4, 36, 12, 4, 37, 13], [6, 43, 15, 2, 44, 16], [3, 36, 12, 8, 37, 13], [7, 42, 14, 4, 43, 15],
    [12, 33, 11, 4, 34, 12], [11, 36, 12, 5, 37, 13], [11, 36, 12, 7, 37, 13], [3, 45, 15, 13, 46, 16],
    [2, 42, 14, 17, 43, 15], [2, 42, 14, 19, 43, 15], [9, 39, 13, 16, 40, 14], [15, 43, 15, 10, 44, 16],
    [19, 46, 16, 6, 47, 17], [34, 37, 13], [16, 45, 15, 14, 46, 16], [30, 46, 16, 2, 47, 17],
    [22, 45, 15, 13, 46, 16], [33, 46, 16, 4, 47, 17], [12, 45, 15, 28, 46, 16], [11, 45, 15, 31, 46, 16],
    [19, 45, 15, 26, 46, 16], [23, 45, 15, 25, 46, 16], [23, 45, 15, 28, 46, 16], [19, 45, 15, 35, 46, 16],
    [11, 45, 15, 46, 46, 16], [59, 46, 16, 1, 47, 17], [22, 45, 15, 41, 46, 16], [2, 45, 15, 64, 46, 16],
    [24, 45, 15, 46, 46, 16], [42, 45, 15, 32, 46, 16], [10, 45, 15, 67, 46, 16], [20, 45, 15, 61, 46, 16]
  ]
  static ALIGNMENT: Array = [
    [], [6, 18], [6, 22],
    [6, 26], [6, 30], [6, 34],
    [6, 22, 38], [6, 24, 42], [6, 26, 46],
    [6, 28, 50], [6, 30, 54], [6, 32, 58],
    [6, 34, 62], [6, 26, 46, 66], [6, 26, 48, 70],
    [6, 26, 50, 74], [6, 30, 54, 78], [6, 30, 56, 82],
    [6, 30, 58, 86], [6, 34, 62, 90], [6, 28, 50, 72, 94],
    [6, 26, 50, 74, 98], [6, 30, 54, 78, 102], [6, 28, 54, 80, 106],
    [6, 32, 58, 84, 110], [6, 30, 58, 86, 114], [6, 34, 62, 90, 118],
    [6, 26, 50, 74, 98, 122], [6, 30, 54, 78, 102, 126], [6, 26, 52, 78, 104, 130],
    [6, 30, 56, 82, 108, 134], [6, 34, 60, 86, 112, 138], [6, 30, 58, 86, 114, 142],
    [6, 34, 62, 90, 118, 146], [6, 30, 54, 78, 102, 126, 150], [6, 24, 50, 76, 102, 128, 154],
    [6, 28, 54, 80, 106, 132, 158], [6, 32, 58, 84, 110, 136, 162], [6, 26, 54, 82, 110, 138, 166],
    [6, 30, 58, 86, 114, 142, 170]
  ]

  static MODULE_SIZE: Int = 11

  # The SVG RQRCode's as_svg(viewbox: true, fill: :white, color: :black) writes.
  static def svg(text)
    code = QrCode.encode(text)
    n = code["size"]
    m = code["modules"]
    size = QrCode.MODULE_SIZE
    dim = str(n * size)
    out = "<?xml version=\"1.0\" standalone=\"yes\"?><svg version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" xmlns:ev=\"http://www.w3.org/2001/xml-events\" viewBox=\"0 0 " +
      dim + " " + dim + "\" shape-rendering=\"crispEdges\"><rect width=\"" + dim + "\" height=\"" + dim + "\" x=\"0\" y=\"0\" fill=\"white\"/>"
    cell = str(size)
    for row in 0..n
      y = str(row * size)
      base = row * n
      for col in 0..n
        if m[base + col] == 1
          out += "<rect width=\"" + cell + "\" height=\"" + cell + "\" x=\"" + str(col * size) + "\" y=\"" + y + "\" fill=\"black\"/>"
        end
      end
    end
    out + "</svg>"
  end

  # {"version", "size", "modules"}: modules is the row-major matrix, 1 dark and 0 light.
  static def encode(text)
    bytes = text.bytes()
    version = QrCode.minimum_version(bytes.length)
    n = version * 4 + 17
    data = QrCode.codewords(bytes, version)

    common = QrCode.function_patterns(version, n)
    # Masks are scored with blank format and version areas, as rqrcode does (make_impl(true, …)).
    blank = common.map { |x| x }
    QrCode.place_format(blank, n, 0, true)
    QrCode.place_version(blank, n, version, true) if version >= 7
    positions = QrCode.data_positions(blank, n)
    bits = QrCode.data_bits(data, positions.length)

    best = 0
    min_lost = 0
    for mask in 0..8
      grid = blank.map { |x| x }
      QrCode.fill(grid, n, positions, bits, mask)
      lost = QrCode.lost_points(grid, n)
      if mask == 0 || min_lost > lost
        min_lost = lost
        best = mask
      end
    end

    grid = common.map { |x| x }
    QrCode.place_format(grid, n, best, false)
    QrCode.place_version(grid, n, version, false) if version >= 7
    QrCode.fill(grid, n, positions, bits, best)
    {"version": version, "size": n, "modules": grid}
  end

  # The smallest version whose level-H capacity holds the byte segment (QRCode#minimum_version).
  static def minimum_version(length)
    for version in 1..41
      header = version < 10 ? 8 : 16
      return version if 4 + header + 8 * length < QrCode.MAX_BITS_H[version - 1]
    end
    throw "Data length exceeds the capacity of a version 40 QR code"
  end

  # --- data codewords ---------------------------------------------------------------------

  static def put_bits(bits, num, length)
    digits = []
    v = num
    for i in 0..length
      digits.push(v % 2)
      v = v / 2
    end
    i = length - 1
    while i >= 0
      bits.push(digits[i])
      i -= 1
    end
    bits
  end

  # QRCode.create_data + create_bytes: the byte segment, terminator, padding, then the
  # data and error correction codewords interleaved across the RS blocks.
  static def codewords(bytes, version)
    blocks = QrCode.rs_blocks(version)
    max_bits = blocks.reduce(fn(acc, b) acc + b["data"], 0) * 8
    bits = []
    QrCode.put_bits(bits, 4, 4)
    QrCode.put_bits(bits, bytes.length, version < 10 ? 8 : 16)
    for b in bytes
      QrCode.put_bits(bits, b, 8)
    end
    QrCode.put_bits(bits, 0, 4) unless bits.length + 4 > max_bits
    throw "code length overflow" if bits.length > max_bits

    while bits.length % 8 != 0
      bits.push(0)
    end
    while bits.length < max_bits
      QrCode.put_bits(bits, 236, 8)
      QrCode.put_bits(bits, 17, 8) if bits.length < max_bits
    end

    buffer = []
    i = 0
    while i < bits.length
      v = 0
      for k in 0..8
        v = v * 2 + bits[i + k]
      end
      buffer.push(v)
      i += 8
    end

    dcdata = []
    ecdata = []
    offset = 0
    max_dc = 0
    max_ec = 0
    for block in blocks
      dc_count = block["data"]
      ec_count = block["total"] - dc_count
      max_dc = dc_count if dc_count > max_dc
      max_ec = ec_count if ec_count > max_ec
      dc = buffer.slice(offset, offset + dc_count)
      offset += dc_count
      dcdata.push(dc)
      ecdata.push(QrCode.error_correction(dc, ec_count))
    end

    out = []
    for i in 0..max_dc
      for dc in dcdata
        out.push(dc[i]) if i < dc.length
      end
    end
    for i in 0..max_ec
      for ec in ecdata
        out.push(ec[i]) if i < ec.length
      end
    end
    out
  end

  static def rs_blocks(version)
    row = QrCode.RS_BLOCKS_H[version - 1]
    list = []
    i = 0
    while i < row.length
      for j in 0..row[i]
        list.push({"total": row[i + 1], "data": row[i + 2]})
      end
      i += 3
    end
    list
  end

  # --- GF(256) and Reed-Solomon -----------------------------------------------------------

  static def xor8(a, b)
    t = QrCode.XOR16
    t[(a / 16) * 16 + b / 16] * 16 + t[(a % 16) * 16 + b % 16]
  end

  static def gmul(a, b)
    return 0 if a == 0 || b == 0

    QrCode.EXP[(QrCode.LOG[a] + QrCode.LOG[b]) % 255]
  end

  # The remainder of data·x^ec by the generator Π(x + α^i), i < ec (QRUtil.get_error_correct_polynomial).
  static def error_correction(data, ec_count)
    gen = [1]
    for i in 0..ec_count
      alpha = QrCode.EXP[i]
      product = [0]
      for g in gen
        product.push(0)
      end
      for j in 0..gen.length
        product[j] = QrCode.xor8(product[j], gen[j])
        product[j + 1] = QrCode.xor8(product[j + 1], QrCode.gmul(gen[j], alpha))
      end
      gen = product
    end

    rem = []
    for i in 0..ec_count
      rem.push(0)
    end
    for d in data
      factor = QrCode.xor8(d, rem[0])
      rem = rem.drop(1)
      rem.push(0)
      if factor != 0
        for i in 0..ec_count
          rem[i] = QrCode.xor8(rem[i], QrCode.gmul(gen[i + 1], factor))
        end
      end
    end
    rem
  end

  # --- module placement -------------------------------------------------------------------

  # Finder patterns with their separators, alignment patterns, timing patterns; -1 elsewhere.
  static def function_patterns(version, n)
    m = []
    for i in 0..(n * n)
      m.push(-1)
    end
    QrCode.place_probe(m, n, 0, 0)
    QrCode.place_probe(m, n, n - 7, 0)
    QrCode.place_probe(m, n, 0, n - 7)

    positions = QrCode.ALIGNMENT[version - 1]
    for row in positions
      for col in positions
        QrCode.place_alignment(m, n, row, col) if m[row * n + col] == -1
      end
    end

    for i in 8..(n - 8)
      v = i % 2 == 0 ? 1 : 0
      m[i * n + 6] = v
      m[6 * n + i] = v
    end
    m
  end

  static def place_alignment(m, n, row, col)
    for r in -2..3
      for c in -2..3
        on = r == 2 || r == -2 || c == 2 || c == -2 || (r == 0 && c == 0)
        m[(row + r) * n + col + c] = on ? 1 : 0
      end
    end
  end

  static def place_probe(m, n, row, col)
    for r in -1..8
      next if row + r < 0 || row + r > n - 1

      for c in -1..8
        next if col + c < 0 || col + c > n - 1

        vertical = r >= 0 && r <= 6 && (c == 0 || c == 6)
        horizontal = c >= 0 && c <= 6 && (r == 0 || r == 6)
        square = r >= 2 && r <= 4 && c >= 2 && c <= 4
        m[(row + r) * n + col + c] = vertical || horizontal || square ? 1 : 0
      end
    end
  end

  static def place_format(m, n, mask, test)
    bits = QrCode.FORMAT_H[mask]
    for i in 0..15
      mod = test ? 0 : (bits / QrCode.POW2[i]) % 2
      row = i < 6 ? i : (i < 8 ? i + 1 : n - 15 + i)
      m[row * n + 8] = mod
      col = i < 8 ? n - i - 1 : (i < 9 ? 15 - i : 14 - i)
      m[8 * n + col] = mod
    end
    m[(n - 8) * n + 8] = test ? 0 : 1
  end

  static def place_version(m, n, version, test)
    bits = QrCode.VERSION_BITS[version]
    for i in 0..18
      mod = test ? 0 : (bits / QrCode.POW2[i]) % 2
      a = i / 3
      b = i % 3 + n - 11
      m[a * n + b] = mod
      m[b * n + a] = mod
    end
  end

  # The cells map_data visits, in order: two-column strips from the right, zigzagging.
  static def data_positions(m, n)
    positions = []
    inc = -1
    row = n - 1
    col = n - 1
    while col >= 1
      c0 = col <= 6 ? col - 1 : col
      while true
        for c in 0..2
          positions.push(row * n + c0 - c) if m[row * n + c0 - c] == -1
        end
        row += inc
        if row < 0 || row >= n
          row -= inc
          inc = -inc
          break
        end
      end
      col -= 2
    end
    positions
  end

  static def data_bits(data, count)
    bits = []
    for k in 0..count
      index = k / 8
      if index < data.length
        bits.push((data[index] / QrCode.POW2[7 - k % 8]) % 2)
      else
        bits.push(0)
      end
    end
    bits
  end

  static def fill(m, n, positions, bits, mask)
    k = 0
    for p in positions
      bit = bits[k]
      m[p] = QrCode.mask?(mask, p / n, p % n) ? 1 - bit : bit
      k += 1
    end
    m
  end

  # QRMASKCOMPUTATIONS
  static def mask?(mask, i, j)
    return (i + j) % 2 == 0 if mask == 0
    return i % 2 == 0 if mask == 1
    return j % 3 == 0 if mask == 2
    return (i + j) % 3 == 0 if mask == 3
    return (i / 2 + j / 3) % 2 == 0 if mask == 4
    return (i * j) % 2 + (i * j) % 3 == 0 if mask == 5
    return ((i * j) % 2 + (i * j) % 3) % 2 == 0 if mask == 6

    ((i * j) % 3 + (i + j) % 2) % 2 == 0
  end

  # --- QRUtil.get_lost_points -------------------------------------------------------------

  static def lost_points(m, n)
    points = 0
    last = n - 1

    # 1: cells with more than five of their (up to eight) neighbours of the same colour.
    across = []
    for r in 0..n
      base = r * n
      for c in 0..n
        s = m[base + c]
        s += m[base + c - 1] if c > 0
        s += m[base + c + 1] if c < last
        across.push(s)
      end
    end
    for r in 0..n
      rows = r > 0 && r < last ? 3 : 2
      for c in 0..n
        cols = c > 0 && c < last ? 3 : 2
        p = r * n + c
        box = across[p]
        box += across[p - n] if r > 0
        box += across[p + n] if r < last
        dark = box - m[p]
        same = m[p] == 1 ? dark : rows * cols - 1 - dark
        points += same - 2 if same > 5
      end
    end

    # 2: 2x2 blocks of one colour.
    for r in 0..last
      base = r * n
      for c in 0..last
        v = m[base + c]
        points += 3 if v == m[base + n + c] && v == m[base + c + 1] && v == m[base + n + c + 1]
      end
    end

    # 3: 1:1:3:1:1 runs (dark, light, dark, dark, dark, light, dark) along rows and columns.
    starts = n - 6
    for r in 0..n
      base = r * n
      for c in 0..starts
        p = base + c
        if m[p] == 1 && m[p + 1] == 0 && m[p + 2] == 1 && m[p + 3] == 1 && m[p + 4] == 1 && m[p + 5] == 0 && m[p + 6] == 1
          points += 40
        end
      end
    end
    for c in 0..n
      for r in 0..starts
        p = r * n + c
        if m[p] == 1 && m[p + n] == 0 && m[p + 2 * n] == 1 && m[p + 3 * n] == 1 && m[p + 4 * n] == 1 && m[p + 5 * n] == 0 && m[p + 6 * n] == 1
          points += 40
        end
      end
    end

    # 4: distance of the dark ratio from 50%, a float as in rqrcode.
    dark_count = m.reduce(fn(acc, x) acc + x, 0)
    ratio = dark_count * 1.0 / (n * n)
    points + (100 * ratio - 50).abs / 5 * 10
  end
end

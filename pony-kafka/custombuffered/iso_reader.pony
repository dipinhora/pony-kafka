/*

Copyright (C) 2016-2017, Sendence LLC
Copyright (C) 2016-2017, The Pony Developers
Copyright (c) 2014-2015, Causality Ltd.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/

class IsoReader is PeekableReader
  """
  Store network data and provide a parsing interface.
  """
  embed _chunks: Array[Array[U8] iso] = _chunks.create()
  var _available: USize = 0
  var _current_node: USize = 0
  var _current_node_offset: USize = 0

  fun size(): USize =>
    """
    Return the number of available bytes.
    """
    _available

  fun ref clear() =>
    """
    Discard all pending data.
    """
    _chunks.clear()
    _available = 0
    _current_node = 0
    _current_node_offset = 0

  fun ref _clean_read() ? =>
    """
    Clean up already read data so GC can do its thing.
    """
    if _current_node_offset > 0 then
      _chunks(_current_node)?.trim_in_place(_current_node_offset)
      _current_node_offset = 0
    end
    if _current_node > 0 then
      _chunks.trim_in_place(_current_node)
      _current_node = 0
    end

  fun ref optimize() ? =>
    """
    Clean up already read data so GC can do its thing.
    """
    _clean_read()?

  fun ref _append(data: ByteSeq iso) =>
    """
    Add a chunk of data.
    """
    try
      _clean_read()?
    end
    let data_array =
      match consume data
      | let data': Array[U8] iso => consume data'
      | let data': String iso => (consume data').iso_array()
      end

    _available = _available + data_array.size()
    _chunks.push(consume data_array)

  fun ref append(data: (ByteSeq iso | Array[ByteSeq iso] iso)) =>
    """
    Add a chunk of data.
    """
    match consume data
    | let data': ByteSeq iso => _append(consume data')
    | let data': Array[ByteSeq iso] iso =>
      let tmp_data = consume ref data'
      // reverse in place to avoid having to do expensive shifts for each element
      tmp_data.reverse_in_place()
      while tmp_data.size() > 0 do
        try
          let d = tmp_data.pop()?
          _append(consume d)
        else
          break
        end
      end
    end

  fun ref append_iso(data: (ByteSeq iso | Array[ByteSeq iso] iso)) =>
    append(consume data)

  fun ref append_val(data: (ByteSeq | Array[ByteSeq] val)) =>
    match data
    | let data': ByteSeq =>
      match data'
      | let d': Array[U8] val => d'.clone()
      | let d': String val => d'.array().clone()
      end
    | let data': Array[ByteSeq] val =>
      for d in data'.values() do
        match d
        | let d': Array[U8] val => d'.clone()
        | let d': String val => d'.array().clone()
        end
      end
    end

  fun ref skip(n: USize) ? =>
    """
    Skip n bytes.
    """
    if _available >= n then
      _available = _available - n
      var rem = n

      while rem > 0 do
        let avail = _chunks(_current_node)?.size() - _current_node_offset

        if avail > rem then
          _current_node_offset = _current_node_offset + rem
          break
        end

        _current_node = _current_node + 1
        _current_node_offset = 0
        rem = rem - avail
      end

    else
      error
    end

  fun ref read_block(len: USize): Array[U8] iso^ ? =>
    """
    Return a block as a contiguous chunk of memory.
    """
    (let num_bytes, let data) = _read_bytes(len)?

    match consume data
    | let a: Array[U8] iso =>
      a
    | let arr: Array[Array[U8] iso] iso =>
      // reverse in place to avoid having to do expensive shifts for each element
      arr.reverse_in_place()
      var out = arr.pop()?
      var i = out.size()
      out.undefined(num_bytes)
      while arr.size() > 0 do
        let a = recover val arr.pop()? end
        out = recover
          let r = consume ref out
          a.copy_to(r, 0, i, a.size())
          i = i + a.size()
          consume r
        end
      end
      out
    end

  fun ref read_until(separator: U8): Array[U8] iso^ ? =>
    """
    Find the first occurrence of the separator and return the block of bytes
    before its position. The separator is not included in the returned array,
    but it is removed from the buffer. To read a line of text, prefer line()
    that handles \n and \r\n.
    """
    let b = read_block(_distance_of(separator)? - 1)?
    read_u8()?
    consume b

  fun ref read_line(keep_line_breaks: Bool = false): String iso^ ? =>
    """
    Return a \n or \r\n terminated line as a string. By default the newline is not
    included in the returned string, but it is removed from the buffer.
    Set `keep_line_breaks` to `true` to keep the line breaks in the returned line.
    """
    let len = _distance_of('\n')?

    let out = read_block(len)?

    let trunc_len: USize =
      if keep_line_breaks then
        0
      elseif (len >= 2) and (out(len - 2)? == '\r') then
        2
      else
        1
      end
    out.truncate(len - trunc_len)

    recover String.from_iso_array(consume out) end

  fun ref read_u8(): U8 ? =>
    """
    Read a U8.
    """
    read_byte()?

  fun ref read_u16(): U16 ? =>
    """
    Read a U16.
    """
    let num_bytes = U16(0).bytewidth()
    if _available < num_bytes then
      error
    end
    if _chunks(_current_node)?.size() >= (num_bytes + _current_node_offset) then
      let r = _chunks(_current_node)?.read_u16(_current_node_offset)?
      if _chunks(_current_node)?.size() > (num_bytes + _current_node_offset) then
        _current_node_offset = _current_node_offset + num_bytes
      else
        _current_node = _current_node + 1
        _current_node_offset = 0
      end
      _available = _available - num_bytes
      r
    else
      // single array did not have all the bytes needed
      ifdef bigendian then
        (read_u8()?.u16() << 8) or read_u8()?.u16()
      else
         read_u8()?.u16() or (read_u8()?.u16() << 8)
      end
    end

  fun ref read_u32(): U32 ? =>
    """
    Read a U32.
    """
    let num_bytes = U32(0).bytewidth()
    if _available < num_bytes then
      error
    end
    if _chunks(_current_node)?.size() >= (num_bytes + _current_node_offset) then
      let r = _chunks(_current_node)?.read_u32(_current_node_offset)?
      if _chunks(_current_node)?.size() > (num_bytes + _current_node_offset) then
        _current_node_offset = _current_node_offset + num_bytes
      else
        _current_node = _current_node + 1
        _current_node_offset = 0
      end
      _available = _available - num_bytes
      r
    else
      // single array did not have all the bytes needed
      ifdef bigendian then
        (read_u8()?.u32() << 24) or (read_u8()?.u32() << 16) or
          (read_u8()?.u32() << 8) or read_u8()?.u32()
      else
        read_u8()?.u32() or (read_u8()?.u32() << 8) or
          (read_u8()?.u32() << 16) or (read_u8()?.u32() << 24)
      end
    end

  fun ref read_u64(): U64 ? =>
    """
    Read a U64.
    """
    let num_bytes = U64(0).bytewidth()
    if _available < num_bytes then
      error
    end
    if _chunks(_current_node)?.size() >= (num_bytes + _current_node_offset) then
      let r = _chunks(_current_node)?.read_u64(_current_node_offset)?
      if _chunks(_current_node)?.size() > (num_bytes + _current_node_offset) then
        _current_node_offset = _current_node_offset + num_bytes
      else
        _current_node = _current_node + 1
        _current_node_offset = 0
      end
      _available = _available - num_bytes
      r
    else
      // single array did not have all the bytes needed
      ifdef bigendian then
        (read_u8()?.u64() << 56) or (read_u8()?.u64() << 48) or
          (read_u8()?.u64() << 40) or (read_u8()?.u64() << 32) or
          (read_u8()?.u64() << 24) or (read_u8()?.u64() << 16) or
          (read_u8()?.u64() << 8) or read_u8()?.u64()
      else
        read_u8()?.u64() or (read_u8()?.u64() << 8) or
          (read_u8()?.u64() << 16) or (read_u8()?.u64() << 24) or
          (read_u8()?.u64() << 32) or (read_u8()?.u64() << 40) or
          (read_u8()?.u64() << 48) or (read_u8()?.u64() << 56)
      end
    end

  fun ref read_u128(): U128 ? =>
    """
    Read a U128.
    """
    let num_bytes = U128(0).bytewidth()
    if _available < num_bytes then
      error
    end
    if _chunks(_current_node)?.size() >= (num_bytes + _current_node_offset) then
      let r = _chunks(_current_node)?.read_u128(_current_node_offset)?
      if _chunks(_current_node)?.size() > (num_bytes + _current_node_offset) then
        _current_node_offset = _current_node_offset + num_bytes
      else
        _current_node = _current_node + 1
        _current_node_offset = 0
      end
      _available = _available - num_bytes
      r
    else
      // single array did not have all the bytes needed
      ifdef bigendian then
        (read_u8()?.u128() << 120) or (read_u8()?.u128() << 112) or
          (read_u8()?.u128() << 104) or (read_u8()?.u128() << 96) or
          (read_u8()?.u128() << 88) or (read_u8()?.u128() << 80) or
          (read_u8()?.u128() << 72) or (read_u8()?.u128() << 64) or
          (read_u8()?.u128() << 56) or (read_u8()?.u128() << 48) or
          (read_u8()?.u128() << 40) or (read_u8()?.u128() << 32) or
          (read_u8()?.u128() << 24) or (read_u8()?.u128() << 16) or
          (read_u8()?.u128() << 8) or read_u8()?.u128()
      else
        read_u8()?.u128() or (read_u8()?.u128() << 8) or
          (read_u8()?.u128() << 16) or (read_u8()?.u128() << 24) or
          (read_u8()?.u128() << 32) or (read_u8()?.u128() << 40) or
          (read_u8()?.u128() << 48) or (read_u8()?.u128() << 56) or
          (read_u8()?.u128() << 64) or (read_u8()?.u128() << 72) or
          (read_u8()?.u128() << 80) or (read_u8()?.u128() << 88) or
          (read_u8()?.u128() << 96) or (read_u8()?.u128() << 104) or
          (read_u8()?.u128() << 112) or (read_u8()?.u128() << 120)
      end
    end

  fun ref read_byte(): U8 ? =>
    """
    Get a single byte.
    """
    let num_bytes = U8(0).bytewidth()
    let r = _chunks(_current_node)?.read_u8(_current_node_offset)?
    _available = _available - num_bytes
    if _chunks(_current_node)?.size() > (num_bytes + _current_node_offset) then
      _current_node_offset = _current_node_offset + num_bytes
    else
      _current_node = _current_node + 1
      _current_node_offset = 0
    end
    r

  fun ref read_bytes(len: USize): (Array[U8] iso^ | Array[Array[U8] iso] iso^) ?
  =>
    _read_bytes(len)?._2

  fun ref _read_bytes(len: USize):
    (USize, (Array[U8] iso^ | Array[Array[U8] iso] iso^)) ?
  =>
    """
    Return a number of bytes as either a contiguous array or an array of arrays
    """
    if len == 0 then
      return (0, recover Array[U8] end)
    end

    if _available < len then
      error
    end

    _clean_read()?

    _available = _available - len
    var data' = _chunks.shift()?

    if data'.size() >= len then
      (let segment, data') = (consume data').chop(len)

      if data'.size() > 0 then
        _chunks.unshift(consume data')
      end

      return (len, consume segment)
    end

    var out = recover Array[Array[U8] iso] end
    var i = data'.size()
    out.push(consume data')

    while i < len do
      var data = _chunks.shift()?
      let avail = data.size()
      let need = len - i
      let copy_len = need.min(avail)

      (let next_segment, data) = (consume data).chop(need)

      out.push(consume next_segment)

      if avail >= need then
        if data.size() > 0 then
          _chunks.unshift(consume data)
        end

        break
      end

      i = i + copy_len
    end

    (i, consume out)

  fun ref read_contiguous_bytes(len: USize): Array[U8] iso^ ? =>
    """
    Return a block as a contiguous chunk of memory without copying if possible
    or copy together multiple chunks if required.
    """
    if len == 0 then
      return recover Array[U8] end
    end

    if _available < len then
      error
    end

    _clean_read()?

    let avail = _chunks(0)?.size()

    // if we have enough data but not in a single contiguous chunk, call `block`
    // to copy chunks together
    if avail < len then
      return read_block(len)?
    end

    var out = recover Array[Array[U8] iso] end

    var data = _chunks.shift()?
    let need = len
    let copy_len = need.min(avail)

    (let next_segment, data) = (consume data).chop(need)
    if data.size() > 0 then
      _chunks.unshift(consume data)
    end
    _available = _available - len
    next_segment

  fun ref peek_u8(offset: USize = 0): U8 ? =>
    """
    Get the U8 at the given offset without moving the cursor forward.
    Raise an error if the given offset is not yet available.
    """
    peek_byte(offset)?

  fun ref peek_u16(offset: USize = 0): U16 ? =>
    """
    Get the U16 at the given offset without moving the cursor forward.
    Raise an error if the given offset is not yet available.
    """
    let num_bytes = U16(0).bytewidth()
    if _available < (offset + num_bytes) then
      error
    end
    try
      var offset' = offset + _current_node_offset
      var current_node' = _current_node

      while true do
        let data_size = _chunks(current_node')?.size()
        if offset' >= data_size then
          offset' = offset' - data_size
          current_node' = current_node' + 1
        else
          return _chunks(current_node')?.read_u16(offset')?
        end
      end

      error
    else
      // single array did not have all the bytes needed
      ifdef bigendian then
        (peek_u8(offset)?.u16() << 8) or peek_u8(offset + 1)?.u16()
      else
         peek_u8(offset)?.u16() or (peek_u8(offset + 1)?.u16() << 8)
      end
    end

  fun ref peek_u32(offset: USize = 0): U32 ? =>
    """
    Get the U32 at the given offset without moving the cursor forward.
    Raise an error if the given offset is not yet available.
    """
    let num_bytes = U32(0).bytewidth()
    if _available < (offset + num_bytes) then
      error
    end
    try
      var offset' = offset + _current_node_offset
      var current_node' = _current_node

      while true do
        let data_size = _chunks(current_node')?.size()
        if offset' >= data_size then
          offset' = offset' - data_size
          current_node' = current_node' + 1
        else
          return _chunks(current_node')?.read_u32(offset')?
        end
      end

      error
    else
      // single array did not have all the bytes needed
      ifdef bigendian then
        (peek_u8(offset)?.u32() << 24) or (peek_u8(offset + 1)?.u32() << 16) or
          (peek_u8(offset + 2)?.u32() << 8) or peek_u8(offset + 3)?.u32()
      else
        peek_u8(offset)?.u32() or (peek_u8(offset + 1)?.u32() << 8) or
          (peek_u8(offset + 2)?.u32() << 16) or (peek_u8(offset + 3)?.u32() << 24)
      end
    end

  fun ref peek_u64(offset: USize = 0): U64 ? =>
    """
    Get the U64 at the given offset without moving the cursor forward.
    Raise an error if the given offset is not yet available.
    """
    let num_bytes = U64(0).bytewidth()
    if _available < (offset + num_bytes) then
      error
    end
    try
      var offset' = offset + _current_node_offset
      var current_node' = _current_node

      while true do
        let data_size = _chunks(current_node')?.size()
        if offset' >= data_size then
          offset' = offset' - data_size
          current_node' = current_node' + 1
        else
          return _chunks(current_node')?.read_u64(offset')?
        end
      end

      error
    else
      // single array did not have all the bytes needed
      ifdef bigendian then
        (peek_u8(offset)?.u64() << 56) or (peek_u8(offset + 1)?.u64() << 48) or
          (peek_u8(offset + 2)?.u64() << 40) or (peek_u8(offset + 3)?.u64() << 32) or
          (peek_u8(offset + 4)?.u64() << 24) or (peek_u8(offset + 5)?.u64() << 16) or
          (peek_u8(offset + 6)?.u64() << 8) or peek_u8(offset + 7)?.u64()
      else
        peek_u8(offset)?.u64() or (peek_u8(offset + 1)?.u64() << 8) or
          (peek_u8(offset + 2)?.u64() << 16) or (peek_u8(offset + 3)?.u64() << 24) or
          (peek_u8(offset + 4)?.u64() << 32) or (peek_u8(offset + 5)?.u64() << 40) or
          (peek_u8(offset + 6)?.u64() << 48) or (peek_u8(offset + 7)?.u64() << 56)
      end
    end

  fun ref peek_u128(offset: USize = 0): U128 ? =>
    """
    Get the U128 at the given offset without moving the cursor forward.
    Raise an error if the given offset is not yet available.
    """
    let num_bytes = U128(0).bytewidth()
    if _available < (offset + num_bytes) then
      error
    end
    try
      var offset' = offset + _current_node_offset
      var current_node' = _current_node

      while true do
        let data_size = _chunks(current_node')?.size()
        if offset' >= data_size then
          offset' = offset' - data_size
          current_node' = current_node' + 1
        else
          return _chunks(current_node')?.read_u128(offset')?
        end
      end

      error
    else
      // single array did not have all the bytes needed
      ifdef bigendian then
        (peek_u8(offset)?.u128() << 120) or (peek_u8(offset + 1)?.u128() << 112) or
          (peek_u8(offset + 2)?.u128() << 104) or (peek_u8(offset + 3)?.u128() << 96) or
          (peek_u8(offset + 4)?.u128() << 88) or (peek_u8(offset + 5)?.u128() << 80) or
          (peek_u8(offset + 6)?.u128() << 72) or (peek_u8(offset + 7)?.u128() << 64) or
          (peek_u8(offset + 8)?.u128() << 56) or (peek_u8(offset + 9)?.u128() << 48) or
          (peek_u8(offset + 10)?.u128() << 40) or (peek_u8(offset + 11)?.u128() << 32) or
          (peek_u8(offset + 12)?.u128() << 24) or (peek_u8(offset + 13)?.u128() << 16) or
          (peek_u8(offset + 14)?.u128() << 8) or peek_u8(offset + 15)?.u128()
      else
        peek_u8(offset)?.u128() or (peek_u8(offset + 1)?.u128() << 8) or
          (peek_u8(offset + 2)?.u128() << 16) or (peek_u8(offset + 3)?.u128() << 24) or
          (peek_u8(offset + 4)?.u128() << 32) or (peek_u8(offset + 5)?.u128() << 40) or
          (peek_u8(offset + 6)?.u128() << 48) or (peek_u8(offset + 7)?.u128() << 56) or
          (peek_u8(offset + 8)?.u128() << 64) or (peek_u8(offset + 9)?.u128() << 72) or
          (peek_u8(offset + 10)?.u128() << 80) or (peek_u8(offset + 11)?.u128() << 88) or
          (peek_u8(offset + 12)?.u128() << 96) or (peek_u8(offset + 13)?.u128() << 104) or
          (peek_u8(offset + 14)?.u128() << 112) or (peek_u8(offset + 15)?.u128() << 120)
      end
    end

  fun ref peek_byte(offset: USize = 0): U8 ? =>
    """
    Get the byte at the given offset without moving the cursor forward.
    Raise an error if the given offset is not yet available.
    """
    if _available < (offset + 1) then
      error
    end

    var offset' = offset + _current_node_offset
    var current_node' = _current_node

    while true do
      let data_size = _chunks(current_node')?.size()
      if offset' >= data_size then
        offset' = offset' - data_size
        current_node' = current_node' + 1
      else
        return _chunks(current_node')?(offset')?
      end
    end

    error

  fun ref peek_bytes(len: USize, offset: USize = 0):
    (Array[U8] val | Array[Array[U8] val] val) ?
  =>
    """
    Return a number of bytes as either a contiguous array or an array of arrays
    without moving the cursor forward
    """
    if _available < (offset + len) then
      error
    end

    var offset' = offset + _current_node_offset
    var current_node' = _current_node

    let x = recover Array[U8] end

    if len == 0 then
      return consume x
    end

    x.reserve(len)

    while true do
      let data_size = _chunks(current_node')?.size()
      if offset' >= data_size then
        offset' = offset' - data_size
        current_node' = current_node' + 1
      else
        if (data_size - offset') > len then
          var s = offset'
          let e = offset' + len
          while s < e do
            x.push(_chunks(current_node')?(s)?)
            s = s + 1
          end
          return consume x
        end

        var i = data_size - offset'

        var s = offset'
        let e = offset' + i
        while s < e do
          x.push(_chunks(current_node')?(s)?)
          s = s + 1
        end

        while i < len do
          current_node' = current_node' + 1
          let avail = _chunks(current_node')?.size()
          let need = len - i
          let copy_len = need.min(avail)

          var s': USize = 0
          let e': USize = copy_len
          while s' < e' do
            x.push(_chunks(current_node')?(s')?)
            s' = s' + 1
          end

          if avail > need then
            return consume x
          end

          i = i + copy_len
        end

        return consume x

      end
    end

    error

  fun ref peek_contiguous_bytes(len: USize, offset: USize = 0): Array[U8] val ? =>
    """
    Return a block as a contiguous chunk of memory without copying if possible
    or copy together multiple chunks if required.
    """
    if _available < (offset + len) then
      error
    end

    var offset' = offset + _current_node_offset
    var current_node' = _current_node

    while true do
      let data_size = _chunks(current_node')?.size()
      if offset' >= data_size then
        offset' = offset' - data_size
      else
        if (data_size - offset') > len then
          let x = recover Array[U8] end
          x.reserve(len)
          var s = offset'
          let e = offset' + len
          while s < e do
            x.push(_chunks(current_node')?(s)?)
            s = s + 1
          end
          return consume x
        end

        let data' = peek_bytes(len, offset)?

        match data'
        | let a: Array[U8] val =>
          return a
        | let arr: Array[Array[U8] val] val =>
          var out = recover Array[U8].>undefined(len) end
          var i: USize = 0
          for a in arr.values() do
            out = recover
              let r = consume ref out
              a.copy_to(r, 0, i, a.size())
              i = i + a.size()
              consume r
            end
          end
          return out
        end

      end

      current_node' = current_node' + 1
    end

    error

  fun ref peek_block(len: USize, offset: USize = 0): Array[U8] iso^ ? =>
    """
    Return a block as a contiguous chunk of memory.
    """
    let num_bytes = len
    let data = peek_bytes(len, offset)?

    match data
    | let a: Array[U8] val =>
      recover a.clone() end
    | let arr: Array[Array[U8] val] val =>
      var out = recover Array[U8].>undefined(num_bytes) end
      var i: USize = 0
      for a in arr.values() do
        out = recover
          let r = consume ref out
          a.copy_to(r, 0, i, a.size())
          i = i + a.size()
          consume r
        end
      end
      out
    end

  fun ref peek_until(separator: U8, offset: USize = 0): Array[U8] iso^ ? =>
    """
    Find the first occurrence of the separator and return the block of bytes
    before its position. The separator is not included in the returned array,
    but it is removed from the buffer. To read a line of text, prefer line()
    that handles \n and \r\n.
    """
    peek_block(_distance_of(separator, offset)? - 1, offset)?

  fun ref peek_line(keep_line_breaks: Bool = false, offset: USize = 0): String iso^ ? =>
    """
    Return a \n or \r\n terminated line as a string. By default the newline is not
    included in the returned string, but it is removed from the buffer.
    Set `keep_line_breaks` to `true` to keep the line breaks in the returned line.
    """
    let len = _distance_of('\n', offset)?

    let out = peek_block(len, offset)?

    let trunc_len: USize =
      if keep_line_breaks then
        0
      elseif (len >= 2) and (out(len - 2)? == '\r') then
        2
      else
        1
      end
    out.truncate(len - trunc_len)

    recover String.from_iso_array(consume out) end

  fun ref _distance_of(byte: U8, offset: USize = 0): USize ? =>
    """
    Get the distance to the first occurrence of the given byte
    """
    if _chunks.size() == 0 then
      error
    end

    _clean_read()?

    var offset': USize = offset
    var search_len: USize = 0
    var current_node': USize = 0

    if offset' > 0 then

      while true do
        let data_size = _chunks(current_node')?.size()
        if offset' >= data_size then
          offset' = offset' - data_size
          current_node' = current_node' + 1
        else
          break
        end
      end

    end

    while true do
      try
        let len = (search_len + _chunks(current_node')?.find(byte, offset')? + 1) - offset'
        search_len = 0
        return len
      end

      search_len = search_len + _chunks(current_node')?.size()

      current_node' = current_node' + 1

      if current_node' > _chunks.size() then
        break
      end
    end

    error

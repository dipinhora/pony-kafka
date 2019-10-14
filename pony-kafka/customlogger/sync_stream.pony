interface val SyncOutStream
  """
  Asnychronous access to some output stream.
  """
  fun tag print(data: ByteSeq)
    """
    Print some bytes and insert a newline afterwards.
    """

  fun tag write(data: ByteSeq)
    """
    Print some bytes without inserting a newline afterwards.
    """

  fun tag printv(data: ByteSeqIter)
    """
    Print an iterable collection of ByteSeqs.
    """

  fun tag writev(data: ByteSeqIter)
    """
    Write an iterable collection of ByteSeqs.
    """

  fun tag flush()
    """
    Flush the stream.
    """

primitive SyncStdoutStream
  """
  Synchronous access to stdout.
  """
  fun tag print(data: ByteSeq) =>
    """
    Print some bytes and insert a newline afterwards.
    """
    _print(data)

  fun tag write(data: ByteSeq) =>
    """
    Print some bytes without inserting a newline afterwards.
    """
    _write(data)

  fun tag printv(data: ByteSeqIter) =>
    """
    Print an iterable collection of ByteSeqs.
    """
    for bytes in data.values() do
      _print(bytes)
    end

  fun tag writev(data: ByteSeqIter) =>
    """
    Write an iterable collection of ByteSeqs.
    """
    for bytes in data.values() do
      _write(bytes)
    end

  fun tag flush() =>
    """
    Flush any data out to the os (ignoring failures).
    """
    @pony_os_std_flush[None](@pony_os_stdout[Pointer[None]]())

  fun tag _write(data: ByteSeq) =>
    """
    Write the bytes without explicitly flushing.
    """
    @pony_os_std_write[None](@pony_os_stdout[Pointer[None]](), data.cpointer(), data.size())

  fun tag _print(data: ByteSeq) =>
    """
    Write the bytes and a newline without explicitly flushing.
    """
    @pony_os_std_print[None](@pony_os_stdout[Pointer[None]](), data.cpointer(), data.size())

primitive SyncStderrStream
  """
  Synchronous access to stderr.
  """
  fun tag print(data: ByteSeq) =>
    """
    Print some bytes and insert a newline afterwards.
    """
    _print(data)

  fun tag write(data: ByteSeq) =>
    """
    Print some bytes without inserting a newline afterwards.
    """
    _write(data)

  fun tag printv(data: ByteSeqIter) =>
    """
    Print an iterable collection of ByteSeqs.
    """
    for bytes in data.values() do
      _print(bytes)
    end

  fun tag writev(data: ByteSeqIter) =>
    """
    Write an iterable collection of ByteSeqs.
    """
    for bytes in data.values() do
      _write(bytes)
    end

  fun tag flush() =>
    """
    Flush any data out to the os (ignoring failures).
    """
    @pony_os_std_flush[None](@pony_os_stderr[Pointer[None]]())

  fun tag _write(data: ByteSeq) =>
    """
    Write the bytes without explicitly flushing.
    """
    @pony_os_std_write[None](@pony_os_stderr[Pointer[None]](), data.cpointer(), data.size())

  fun tag _print(data: ByteSeq) =>
    """
    Write the bytes and a newline without explicitly flushing.
    """
    @pony_os_std_print[None](@pony_os_stderr[Pointer[None]](), data.cpointer(), data.size())

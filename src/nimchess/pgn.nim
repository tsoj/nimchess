import strchess, movegen, position, game
import std/[strutils, options, strformat, streams, tables, sequtils]

export game, position, move
export tables, streams

proc parseHeaders(stream: Stream): Table[string, string] =
  result = initTable[string, string]()
  var line = ""

  while not stream.atEnd():
    let currentPos = stream.getPosition()
    line = stream.readLine().strip()
    if line.len == 0:
      continue

    if not line.startsWith("["):
      # Put back the line by seeking back
      stream.setPosition(currentPos)
      break

    if not line.endsWith("]"):
      raise newException(ValueError, "Invalid header format: " & line)

    let headerContent = line[1 ..^ 2] # Remove [ and ]
    let spacePos = headerContent.find(' ')
    if spacePos == -1:
      raise newException(ValueError, "Invalid header format: " & line)

    let key = headerContent[0 ..< spacePos]
    var value = headerContent[spacePos + 1 ..^ 1].strip()

    # Remove quotes if present
    if value.startsWith("\"") and value.endsWith("\""):
      value = value[1 ..^ 2]

    result[key] = value

type CommentState = object
  comments: seq[string]
  closeChars: seq[char]

func isInComment(state: var CommentState): bool =
  state.closeChars.len > 0

proc cleanLineOfComments(line: string, state: var CommentState): string =
  result = ""

  template finalizeComment() =
    state.comments[^1] = state.comments[^1].strip()
    result.add fmt" $${state.comments.len - 1} "

  if state.isInComment:
    state.comments[^1].add ' '

  for i, c in line:
    if state.isInComment:
      if c == state.closeChars[^1]:
        state.closeChars.setLen(state.closeChars.len - 1)
        if state.closeChars.len == 0:
          finalizeComment()
      else:
        if state.closeChars[^1] == ')' and c == '(': # to support parsing RAV
          state.closeChars.add ')'
        doAssert state.comments.len > 0
        state.comments[^1].add c
    else:
      if c == ';':
        let rest = line[i + 1 ..^ 1]
        if rest.len > 0:
          state.comments.add rest
          finalizeComment()
        break
      elif c in ['(', '{']:
        state.comments.add ""
        state.closeChars.add(if c == '(': ')' else: '}')
      else:
        result.add c

proc parseMoveText(
    stream: Stream, startPos: Position
): (seq[tuple[move: Move, annotation: string]], string, string) =
  ## Returns (annotated moves, game result, pre-move comment)
  var
    annotatedMoves: seq[tuple[move: Move, annotation: string]] = @[]
    position = startPos
    content = ""
    commentState: CommentState
    gameResult = none string

  const resultTokens = ["1-0", "0-1", "1/2-1/2", "*"]

  # Read until we hit the next game, game result, or end of stream
  while not stream.atEnd() and gameResult.isNone:
    let currentPos = stream.getPosition()
    let line = stream.readLine()

    # Clean the line of comments first, capturing comment text
    let cleanLine = cleanLineOfComments(line, commentState).strip()

    # If we hit a line starting with [, it's the next game's headers (only check if not in comment)
    if not commentState.isInComment and cleanLine.startsWith("["):
      # Put the line back by seeking to its start
      stream.setPosition(currentPos)
      break

    # Check for game results in the clean line
    let tokens = cleanLine.split()
    for token in tokens:
      if token in resultTokens:
        gameResult = some token
        break

    content.add(cleanLine & " ")

  # Clean up the move text further
  content = content.multiReplace(({'\n', '\r', '\t', '.', '!', '?', '+', '#'}, ' '))

  # Split into tokens
  let tokens = content.split().filterIt(it.len > 0)

  var preMoveComment = ""

  template appendComment(target: var string, comment: string) =
    if target.len > 0:
      target.add(" ")
    target.add(comment)

  for token in tokens:
    # Handle $$<n> comment markers
    if token.startsWith("$$"):
      let comment = commentState.comments[parseInt(token[2 ..^ 1])]
      if annotatedMoves.len > 0:
        annotatedMoves[^1].annotation.appendComment(comment)
      else:
        preMoveComment.appendComment(comment)
      continue

    # Skip empty tokens or pure numbers or special $ markers
    if token.len == 0 or token.allIt(it.isDigit()) or token in resultTokens or
        token.startsWith("$"):
      continue

    let move = toMove(token, position)
    annotatedMoves.add((move: move, annotation: ""))
    position = position.doMove(move, allowNullMove = true)

  return (annotatedMoves, gameResult.get(otherwise = "*"), preMoveComment)

proc readSingleGameFromPgn(stream: Stream): Game =
  if stream.atEnd():
    raise newException(ValueError, "Can't read PGN from finished stream")

  let headers = parseHeaders(stream)

  # Determine starting position
  let startPos =
    if "FEN" in headers:
      toPosition(headers["FEN"])
    else:
      toPosition("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

  let (annotatedMoves, gameResult, preMoveComment) = parseMoveText(stream, startPos)

  var finalHeaders = headers
  if preMoveComment.len > 0:
    var key = "PreMoveComment"
    if key in finalHeaders:
      var n = 1
      while key & $n in finalHeaders:
        n += 1
      key = key & $n
    finalHeaders[key] = preMoveComment

  result = Game(
    headers: finalHeaders,
    annotatedMoves: annotatedMoves,
    startPosition: startPos,
    result: gameResult,
  )

iterator readPgnFromStreamIter*(stream: Stream, suppressWarnings = false): Game =
  var lastGoodPosition = 0

  while not stream.atEnd():
    # Skip empty lines
    var line = ""
    while not stream.atEnd():
      let pos = stream.getPosition()
      line = stream.readLine().strip()
      if line.len > 0:
        stream.setPosition(pos)
        break

    if stream.atEnd():
      break

    try:
      let game = readSingleGameFromPgn(stream)
      lastGoodPosition = stream.getPosition()
      yield game
    except ValueError:
      if not suppressWarnings:
        let currentPos = stream.getPosition()
        stream.setPosition(0)
        var
          lineNumberEnd = 1
          lineNumberStart = 1
        for i in 0 ..< currentPos:
          if stream.readChar() == '\n':
            lineNumberEnd += 1
            if i <= lastGoodPosition:
              lineNumberStart += 1

        assert currentPos == stream.getPosition()
        echo &"WARNING: Failed to read game between lines {lineNumberStart} and {lineNumberEnd}\n--> ",
          getCurrentException().msg

iterator readPgnFileIter*(filename: string, suppressWarnings = false): Game =
  let fileStream = newFileStream(filename, fmRead)
  if fileStream == nil:
    raise newException(IOError, fmt"Couldn't open file: {filename}")
  for game in readPgnFromStreamIter(fileStream, suppressWarnings = suppressWarnings):
    yield game

proc readPgnFromStream*(stream: StringStream, suppressWarnings = false): seq[Game] =
  for game in stream.readPgnFromStreamIter(suppressWarnings = suppressWarnings):
    result.add game

proc readPgnFromString*(content: string, suppressWarnings = false): seq[Game] =
  let stream = newStringStream(content)
  defer:
    stream.close()
  return readPgnFromStream(stream, suppressWarnings = suppressWarnings)

proc readPgnFile*(filename: string, suppressWarnings = false): seq[Game] =
  let content = readFile(filename)
  return readPgnFromString(content, suppressWarnings = suppressWarnings)

func toPgnString*(game: Game): string =
  result = ""

  const canonicalOrder = ["Event", "Site", "Date", "Round", "White", "Black", "Result"]

  for key in canonicalOrder:
    if key in game.headers:
      result &= &"[{key} \"{game.headers[key]}\"]\n"

  # Add headers
  for key, value in game.headers:
    if key notin canonicalOrder:
      result &= &"[{key} \"{value}\"]\n"

  # Add empty line after headers
  if game.headers.len > 0:
    result &= "\n"

  # Add moves
  var position = game.startPosition

  if position.us == black:
    result &= fmt"{position.currentFullmoveNumber}... "

  for i, am in game.annotatedMoves:
    # Add move number for white moves
    if position.us == white:
      result &= fmt"{position.currentFullmoveNumber}. "

    # Add the move in SAN notation
    result &= am.move.toSAN(position)

    # Add annotation as comment if present
    if am.annotation.len > 0:
      if '}' in am.annotation:
        result &= " (" & am.annotation & ")"
      else:
        result &= " {" & am.annotation & "}"

    # Add space after move (except for last move)
    if i < game.annotatedMoves.len - 1:
      result &= " "

    # Add line break every few moves for readability
    if i mod 16 == 15: # Line break every 8 move pairs
      result &= "\n"

    position = position.doMove(am.move, allowNullMove = true)

  # Add result
  if game.result != "":
    if game.annotatedMoves.len > 0:
      result &= " "
    result &= game.result

  result &= "\n"

func toPgnString*(games: seq[Game]): string =
  for game in games:
    result &= game.toPgnString & "\n\n"

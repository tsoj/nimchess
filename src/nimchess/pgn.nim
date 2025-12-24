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

func isInComment(x: Table[char, int]): bool =
  x['{'] > 0 or x['('] > 0

# Helper function to clean a line of comments
proc cleanLineOfComments(line: string, commentDepth: var Table[char, int]): string =
  result = ""

  for c in line:
    let d = {'}': '{', ')': '('}.toTable.getOrDefault(c, 'x')

    if c == ';' and not commentDepth.isInComment:
      # Rest of line is comment
      break
    elif c in commentDepth:
      commentDepth[c] += 1
    elif d in commentDepth and commentDepth[d] > 0:
      commentDepth[d] -= 1
    elif not commentDepth.isInComment:
      result.add(c)

proc parseMoveText(stream: Stream, startPos: Position): (seq[Move], string) =
  var
    moves: seq[Move] = @[]
    position = startPos
    content = ""
    commentDepth = {'{': 0, '(': 0}.toTable
    gameResult = none string

  const resultTokens = ["1-0", "0-1", "1/2-1/2", "*"]

  # Read until we hit the next game, game result, or end of stream
  while not stream.atEnd() and gameResult.isNone:
    let currentPos = stream.getPosition()
    let line = stream.readLine()

    # Clean the line of comments first
    let cleanLine = cleanLineOfComments(line, commentDepth).strip()

    # If we hit a line starting with [, it's the next game's headers (only check if not in comment)
    if not commentDepth.isInComment and cleanLine.startsWith("["):
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

  for token in tokens:
    # Skip empty tokens or pure numbers or special $ markers
    if token.len == 0 or token.allIt(it.isDigit()) or token in resultTokens or
        token.startsWith("$"):
      continue

    let move = toMove(token, position)
    moves.add(move)
    position = position.doMove(move, allowNullMove = true)

  return (moves, gameResult.get(otherwise = "*"))

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

  let (moves, gameResult) = parseMoveText(stream, startPos)

  result =
    Game(headers: headers, moves: moves, startPosition: startPos, result: gameResult)

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

  for i, move in game.moves:
    # Add move number for white moves
    if position.us == white:
      result &= fmt"{position.currentFullmoveNumber}. "

    # Add the move in SAN notation
    result &= move.toSAN(position)

    # Add space after move (except for last move)
    if i < game.moves.len - 1:
      result &= " "

    # Add line break every few moves for readability
    if i mod 16 == 15: # Line break every 8 move pairs
      result &= "\n"

    position = position.doMove(move, allowNullMove = true)

  # Add result
  if game.result != "":
    if game.moves.len > 0:
      result &= " "
    result &= game.result

  result &= "\n"

func toPgnString*(games: seq[Game]): string =
  for game in games:
    result &= game.toPgnString & "\n\n"

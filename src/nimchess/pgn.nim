import strchess, movegen, position, game
import std/[strutils, options, strformat, streams, tables, sequtils]

export game, position, move
export tables, streams

func toSAN*(move: Move, position: Position): string =
  if move.isNoMove:
    return "Z0"

  result = ""

  let
    newPosition = position.doMove move
    moveFile = ($move.source)[0]
    moveRank = ($move.source)[1]
    moved = move.moved(position)
    captured = move.captured(position)

  if moved != pawn:
    result = moved.notation.toUpperAscii

  for (fromFile, fromRank) in [
    (none char, none char),
    (some moveFile, none char),
    (none char, some moveRank),
    (some moveFile, some moveRank),
  ]:
    proc isDisambiguated(): bool =
      if moved == pawn and fromFile.isNone and captured != noPiece:
        return false

      for otherMove in position.legalMoves:
        let
          otherMoveFile = ($otherMove.source)[0]
          otherMoveRank = ($otherMove.source)[1]

        if otherMove.moved(position) == moved and otherMove.target == move.target and
            otherMove.source != move.source and
            fromFile.get(otherwise = otherMoveFile) == otherMoveFile and
            fromRank.get(otherwise = otherMoveRank) == otherMoveRank:
          return false

      true

    if isDisambiguated():
      if fromFile.isSome:
        result &= $get(fromFile)
      if fromRank.isSome:
        result &= $get(fromRank)
      break

  if captured != noPiece:
    result &= "x"

  result &= $move.target

  if move.promoted != noPiece:
    result &= "=" & move.promoted.notation.toUpperAscii

  if move.isCastling:
    if move.castlingSide(position) == queenside:
      result = "O-O-O"
    else:
      result = "O-O"

  let inCheck = newPosition.inCheck(newPosition.us)
  if newPosition.legalMoves.len == 0:
    if inCheck:
      result &= "#"
    else:
      result &= " 1/2-1/2"
  else:
    if inCheck:
      result &= "+"
    if newPosition.halfmoveClock > 100:
      result &= " 1/2-1/2"

func notationSAN*(pv: seq[Move], position: Position): string =
  result = ""
  var currentPosition = position
  for move in pv:
    result &= move.toSAN(currentPosition) & " "
    currentPosition = currentPosition.doMove(move)

func validSANMove(position: Position, move: Move, san: string): bool =
  if san.len <= 1:
    return false

  # Find first non-whitespace segment without creating new strings
  var start = 0
  while start < san.len and san[start] in {' ', '\t', '\n', '\r'}:
    inc start

  var endPos = start + 1
  while endPos + 1 < san.len and san[endPos + 1] notin {' ', '\t', '\n', '\r', '+', '#'}:
    inc endPos

  if start > endPos:
    return false

  # Check for castling moves
  if endPos - start + 1 >= 5 and san[start .. start + 4] == "O-O-O":
    return
      move.isCastling and move.target == position.rookSource[position.us][queenside]
  elif endPos - start + 1 >= 3 and san[start .. start + 2] == "O-O":
    return move.isCastling and move.target == position.rookSource[position.us][kingside]

  # Parse piece type
  var pieceChar: char
  var pos = start

  if san[pos].isUpperAscii:
    pieceChar = san[pos]
    inc pos
  else:
    pieceChar = 'P' # Pawn move

  let moved = pieceChar.toColoredPiece.piece

  # Look for capture indicator and promotion, working backwards
  var
    isCapture = false
    promoted = noPiece
    targetEnd = endPos

  # Check for promotion (=X at the end)
  if targetEnd - 1 >= pos and san[targetEnd - 1] == '=':
    promoted = san[targetEnd].toColoredPiece.piece
    targetEnd -= 2

  # Must have at least 2 chars for target square
  if targetEnd - 1 < pos:
    return false

  # Extract target square from last 2 positions
  let target = parseEnum[Square](san[targetEnd - 1 .. targetEnd])
  targetEnd -= 2

  # Check for capture and source disambiguation
  var
    sourceRank = not 0.Bitboard
    sourceFile = not 0.Bitboard

  while pos <= targetEnd:
    let c = san[pos]
    case c
    of 'x':
      isCapture = true
    of '1' .. '8':
      sourceRank = ranks(parseEnum[Square]("a" & $c))
    of 'a' .. 'h':
      sourceFile = files(parseEnum[Square]($c & "1"))
    else:
      discard # Skip other characters like annotations
    inc pos

  move.moved(position) == moved and (move.captured(position) != noPiece) == isCapture and
    move.promoted == promoted and move.target == target and
    not empty(sourceRank and sourceFile and move.source.toBitboard)

func toMoveFromSAN*(sanMove: string, position: Position): Move =
  if sanMove.strip() in ["Z0", "--", "0000"]:
    return noMove

  result = noMove
  for move in position.legalMoves:
    if validSANMove(position, move, sanMove):
      if not result.isNoMove:
        raise newException(
          ValueError,
          fmt"Ambiguous SAN move notation: {sanMove} (possible moves: {result}, {move}",
        )
      result = move

  if result.isNoMove:
    try:
      result = sanMove.toMove(position)
    except ValueError:
      raise newException(ValueError, fmt"Illegal SAN notation: {sanMove}")

proc parseHeaders(stream: Stream): Table[string, string] =
  result = initTable[string, string]()
  var line = ""

  while not stream.atEnd():
    line = stream.readLine().strip()
    if line.len == 0:
      continue

    if not line.startsWith("["):
      # Put back the line by seeking back
      let currentPos = stream.getPosition()
      stream.setPosition(currentPos - line.len - 1)
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

# Helper function to clean a line of comments
proc cleanLineOfComments(line: string, inBraceCommentDepth: var int): string =
  result = ""

  for c in line:
    if c == ';':
      # Rest of line is comment
      break
    elif c in ['}', ')']:
      inBraceCommentDepth -= 1
    elif c in ['{', '(']:
      inBraceCommentDepth += 1
    elif inBraceCommentDepth == 0:
      result.add(c)

proc parseMoveText(stream: Stream, startPos: Position): (seq[Move], string) =
  var
    moves: seq[Move] = @[]
    position = startPos
    content = ""
    inBraceCommentDepth = 0
    gameResult = none string

  const resultTokens = ["1-0", "0-1", "1/2-1/2", "*"]

  # Read until we hit the next game, game result, or end of stream
  while not stream.atEnd() and gameResult.isNone:
    let currentPos = stream.getPosition()
    let line = stream.readLine()

    # Clean the line of comments first
    let cleanLine = cleanLineOfComments(line, inBraceCommentDepth).strip()

    # If we hit a line starting with [, it's the next game's headers (only check if not in comment)
    if inBraceCommentDepth == 0 and cleanLine.startsWith("["):
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
  content = content.multiReplace(
    [
      ("\n", " "),
      ("\r", " "),
      ("\t", " "),
      (".", " "),
      ("!", " "),
      ("?", " "),
      ("+", " "),
      ("#", " "),
    ]
  )

  # Split into tokens
  let tokens = content.split().filterIt(it.len > 0)

  for token in tokens:
    var cleanToken = token

    # Skip empty tokens or pure numbers
    if cleanToken.len == 0 or cleanToken.allIt(it.isDigit()) or
        cleanToken in resultTokens or cleanToken.startsWith("$"):
      continue

    let move = toMoveFromSAN(cleanToken, position)
    moves.add(move)
    position = position.doMove(move, allowNullMove = true)

  return (moves, gameResult.get(otherwise = "*"))

proc parseGame*(stream: Stream): Game =
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

iterator parseGamesFromStreamIter*(stream: Stream, suppressWarnings = false): Game =
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
      let game = parseGame(stream)
      yield game
    except ValueError:
      if not suppressWarnings:
        let currentPos = stream.getPosition()
        stream.setPosition(0)
        var lineNumber = 1
        for i in 0 ..< currentPos:
          if stream.readChar() == '\n':
            lineNumber += 1

        assert currentPos == stream.getPosition()
        echo &"WARNING: Failed to read game before line {lineNumber}\n--> ",
          getCurrentException().msg

iterator parseGamesFromFileIter*(filename: string, suppressWarnings = false): Game =
  let fileStream = newFileStream(filename, fmRead)
  if fileStream == nil:
    raise newException(IOError, fmt"Couldn't open file: {filename}")
  for game in parseGamesFromStreamIter(fileStream, suppressWarnings = suppressWarnings):
    yield game

proc parseGamesFromStream*(stream: StringStream, suppressWarnings = false): seq[Game] =
  for game in stream.parseGamesFromStreamIter(suppressWarnings = suppressWarnings):
    result.add game

proc parseGamesFromString*(content: string, suppressWarnings = false): seq[Game] =
  let stream = newStringStream(content)
  defer:
    stream.close()
  return parseGamesFromStream(stream, suppressWarnings = suppressWarnings)

proc parseGamesFromFile*(filename: string, suppressWarnings = false): seq[Game] =
  let content = readFile(filename)
  return parseGamesFromString(content, suppressWarnings = suppressWarnings)

func toPgnString*(game: Game): string =
  result = ""

  # Add headers
  for key, value in game.headers:
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

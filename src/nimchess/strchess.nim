import types, position, move, movegen, bitboard, castling

import std/[strutils, options, strformat]

export move, position

func fen*(position: Position, alwaysShowEnPassantSquare: bool = false): string =
  result = ""
  var emptySquareCounter = 0
  for rank in countdown(7, 0):
    for file in 0 .. 7:
      let square = (rank * 8 + file).Square
      let coloredPiece = position.coloredPieceAt(square)
      if coloredPiece.piece != noPiece:
        if emptySquareCounter > 0:
          result &= $emptySquareCounter
          emptySquareCounter = 0
        result &= coloredPiece.notation
      else:
        emptySquareCounter += 1
    if emptySquareCounter > 0:
      result &= $emptySquareCounter
      emptySquareCounter = 0
    if rank != 0:
      result &= "/"

  result &= (if position.us == white: " w " else: " b ")

  for color in [white, black]:
    for castlingSide in [kingside, queenside]:
      let rookSource = position.rookSource[color][castlingSide]
      if rookSource != noSquare:
        result &= ($rookSource)[0]

        if result[^1] == 'h':
          result[^1] = 'k'
        if result[^1] == 'a':
          result[^1] = 'q'

        if color == white:
          result[^1] = result[^1].toUpperAscii

  if result.endsWith(' '):
    result &= "-"

  result &= " "

  var enPassantStr = "-"
  # debugEcho result
  for move in position.legalMoves:
    if move.isEnPassantCapture:
      assert move.target == position.enPassantTarget
      enPassantStr = $position.enPassantTarget
  if alwaysShowEnPassantSquare and position.enPassantTarget != noSquare:
    enPassantStr = $position.enPassantTarget
  result &= enPassantStr

  result &= " " & $position.halfmoveClock & " " & $position.currentFullmoveNumber

func `$`*(position: Position): string =
  result =
    boardString(
      proc(square: Square): Option[string] =
        if not empty(square.toBitboard and position.occupancy):
          return some($position.coloredPieceAt(square))
        none(string)
    ) & "\n"
  let fenWords = position.fen.splitWhitespace
  for i in 1 ..< fenWords.len:
    result &= fenWords[i] & " "

func debugString*(position: Position): string =
  result = ""
  for piece in pawn .. king:
    result &= $piece & ":\n"
    result &= $position[piece] & "\n"
  for color in white .. black:
    result &= $color & ":\n"
    result &= $position[color] & "\n"
  result &= "enPassantTarget:\n"
  result &= $position.enPassantTarget & "\n"
  result &= "us: " & $position.us & ", enemy: " & $position.enemy & "\n"
  result &=
    "halfmovesPlayed: " & $position.halfmovesPlayed & ", halfmoveClock: " &
    $position.halfmoveClock & "\n"
  result &= "zobristKey: " & $position.zobristKey & "\n"
  result &= "rookSource: " & $position.rookSource

proc toPosition*(fen: string, suppressWarnings = false): Position =
  result = default(Position)

  var fenWords = fen.splitWhitespace()
  if fenWords.len < 4:
    raise newException(ValueError, "FEN must have at least 4 words")
  if fenWords.len > 6 and not suppressWarnings:
    echo "WARNING: FEN shouldn't have more than 6 words"
  while fenWords.len < 6:
    fenWords.add("0")

  for i in 2 .. 8:
    fenWords[0] = fenWords[0].replace($i, repeat("1", i))

  let piecePlacement = fenWords[0]
  let activeColor = fenWords[1]
  let castlingRights = fenWords[2]
  let enPassant = fenWords[3]
  let halfmoveClock = fenWords[4]
  let fullmoveNumber = fenWords[5]

  var squareList = block:
    var squareList = default(seq[Square])
    for y in 0 .. 7:
      for x in countdown(7, 0):
        squareList.add Square(y * 8 + x)
    squareList

  for pieceChar in piecePlacement:
    if squareList.len == 0:
      raise
        newException(ValueError, "FEN is not correctly formatted (too many squares)")

    case pieceChar
    of '/':
      # we don't need to do anything, except check if the / is at the right place
      if not squareList[^1].isLeftEdge:
        raise newException(ValueError, "FEN is not correctly formatted (misplaced '/')")
    of '1':
      discard squareList.pop
    of '0':
      if not suppressWarnings:
        echo "WARNING: '0' in FEN piece placement data is not official notation"
    else:
      doAssert pieceChar notin ['2', '3', '4', '5', '6', '7', '8']
      try:
        let sq = squareList.pop
        result.addColoredPiece(pieceChar.toColoredPiece, sq)
      except ValueError:
        raise newException(
          ValueError,
          "FEN piece placement is not correctly formatted: " & getCurrentExceptionMsg(),
        )

  if squareList.len != 0:
    raise newException(ValueError, "FEN is not correctly formatted (too few squares)")

  # active color
  case activeColor
  of "w", "W":
    result.us = white
  of "b", "B":
    result.us = black
  else:
    raise newException(
      ValueError, "FEN active color notation does not exist: " & activeColor
    )

  # castling rights
  result.rookSource = [[noSquare, noSquare], [noSquare, noSquare]]
  for castlingChar in castlingRights:
    if castlingChar == '-':
      continue

    let
      us = if castlingChar.isUpperAscii: white else: black
      kingSquare = result.kingSquare(us)

    if kingSquare == noSquare:
      echo fmt"WARNING: Castling notation exists for {us} despite no available king"
      continue

    let rookSource =
      case castlingChar
      of 'K', 'k', 'Q', 'q':
        let (makeStep, atEdge) =
          if castlingChar in ['K', 'k']:
            (types.right, isRightEdge)
          else:
            (types.left, isLeftEdge)
        var
          square = kingSquare
          rookSource = noSquare
        while not square.atEdge:
          square = square.makeStep
          if not empty(result[rook, us] and square.toBitboard):
            rookSource = square
        rookSource
      else:
        let rookSourceBit =
          file(parseEnum[Square](castlingChar.toLowerAscii & "1")) and homeRank(us)

        if rookSourceBit.countSetBits != 1:
          raise newException(
            ValueError,
            fmt"FEN castling erroneous. Invalid castling char: {castlingChar}",
          )

        rookSourceBit.toSquare

    let castlingSide = if rookSource < kingSquare: queenside else: kingside
    result.rookSource[us][castlingSide] = rookSource
    if rookSource == noSquare or empty (rookSource.toBitboard and result[us, rook]):
      raise newException(
        ValueError,
        fmt"FEN castling erroneous. Rook for {us} for {castlingSide} doesn't exist",
      )

  # en passant square
  result.enPassantTarget = noSquare
  if enPassant != "-":
    try:
      result.enPassantTarget = parseEnum[Square](enPassant.toLowerAscii)
    except ValueError:
      raise newException(
        ValueError,
        "FEN en passant target square is not correctly formatted: " &
          getCurrentExceptionMsg(),
      )

  # halfmove clock and fullmove number
  try:
    result.halfmoveClock = halfmoveClock.parseInt
  except ValueError:
    raise newException(
      ValueError,
      "FEN halfmove clock is not correctly formatted: " & getCurrentExceptionMsg(),
    )

  try:
    result.halfmovesPlayed = (fullmoveNumber.parseInt - 1) * 2
    if result.us == black:
      result.halfmovesPlayed += 1
  except ValueError:
    raise newException(
      ValueError,
      "FEN fullmove number is not correctly formatted: " & getCurrentExceptionMsg(),
    )

  result.setZobristKeys

  if result[white, king].countSetBits != 1 or result[black, king].countSetBits != 1:
    if not suppressWarnings:
      echo "WARNING: FEN is not correctly formatted: Need exactly one king for each color"

func toUCI*(move: Move, position: Position): string =
  if move.isCastling and not position.isChess960:
    return $move.source & $castlingKingTarget(position.us, move.castlingSide(position))
  $move

func toMoveFromUCI*(s: string, position: Position): Move =
  if s.len != 4 and s.len != 5:
    raise newException(ValueError, "Move string is wrong length: " & s)

  let
    source = parseEnum[Square](s[0 .. 1])
    target = parseEnum[Square](s[2 .. 3])
    promoted =
      if s.len == 5:
        s[4].toColoredPiece.piece
      else:
        noPiece

  for move in position.legalMoves:
    if move.source == source and move.promoted == promoted:
      if move.target == target:
        return move
      if move.isCastling and
          target == castlingKingTarget(position.us, move.castlingSide(position)) and
          not position.isChess960:
        return move
  raise newException(ValueError, "Move is illegal: " & s)

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

  proc toSquare(s: string): Square =
    try:
      parseEnum[Square](s)
    except ValueError:
      noSquare

  # Extract target square from last 2 positions
  let target = san[targetEnd - 1 .. targetEnd].toSquare
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
      sourceRank = rank(toSquare("a" & $c))
    of 'a' .. 'h':
      sourceFile = file(toSquare($c & "1"))
    else:
      discard # Skip other characters like annotations
    inc pos

  move.moved(position) == moved and (move.captured(position) != noPiece) == isCapture and
    move.promoted == promoted and move.target == target and
    not empty(sourceRank and sourceFile and move.source.toBitboard)

func toMove*(moveNotation: string, position: Position): Move =
  if moveNotation.strip() in ["Z0", "--", "0000"]:
    return noMove

  result = noMove
  for move in position.legalMoves:
    if validSANMove(position, move, moveNotation):
      if not result.isNoMove:
        raise newException(
          ValueError,
          fmt"Ambiguous SAN move notation: {moveNotation} (possible moves: {result}, {move})",
        )
      result = move

  if result.isNoMove:
    try:
      result = moveNotation.toMoveFromUCI(position)
    except ValueError:
      raise newException(ValueError, fmt"Illegal move notation: {moveNotation}")

func notation*(
    pv: seq[Move],
    position: Position,
    toFunc: proc(move: Move, position: Position): string {.noSideEffect.} = toUCI,
): string =
  result = ""
  var currentPosition = position
  for move in pv:
    result &= move.toFunc(currentPosition) & " "
    currentPosition = currentPosition.doMove(move)

func doMove*(position: Position, moveString: string): Position =
  position.doMove(moveString.toMove(position))

const classicalStartPos* =
  "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".toPosition

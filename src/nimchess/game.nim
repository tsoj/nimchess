import position, move, strchess, movegen
import std/tables

export position, move
export tables

type Game* = object
  headers*: Table[string, string]
  moves*: seq[Move]
  startPosition*: Position = classicalStartPos
  result*: string = "*"

func positions*(game: Game): seq[Position] =
  result = @[game.startPosition]
  for move in game.moves:
    result.add result[^1].doMove(move)

func currentPosition*(game: Game): Position =
  ## Get the current position after all moves have been played
  if game.moves.len == 0:
    return game.startPosition
  return game.positions[^1]

func getTargetIndex*(game: Game, moveIndex: int = -1): int =
  ## Helper function to get the target index for a move.
  ## If moveIndex is -1, returns the current position index.
  let positions = game.positions()
  let targetIndex =
    if moveIndex <= -1:
      positions.len + moveIndex
    else:
      moveIndex

  if targetIndex < 0 or targetIndex >= positions.len:
    raise newException(IndexDefect, "Move index out of bounds")

  targetIndex

func repetitionCount*(game: Game, moveIndex: int = -1): int =
  ## Count how many times the position at moveIndex appears in the game.
  ## If moveIndex is -1, counts the current position.
  let positions = game.positions()
  let targetIndex = game.getTargetIndex(moveIndex)

  let targetPosition = positions[targetIndex]

  for pos in positions[0 .. targetIndex]:
    if pos ~ targetPosition:
      result += 1

func hasRepetition*(game: Game, moveIndex: int = -1): bool =
  ## Check if there's a threefold repetition at the given move index.
  ## If moveIndex is -1, checks at the current position.
  game.repetitionCount(moveIndex = moveIndex) >= 3

func fivefoldRepetition*(game: Game, moveIndex: int = -1): bool =
  ## Check if there's a fivefold repetition at the given move index (mandatory draw).
  ## If moveIndex is -1, checks at the current position.
  game.repetitionCount(moveIndex = moveIndex) >= 5

func fiftyMoveRule*(game: Game, moveIndex: int = -1): bool =
  ## Check if the 50-move rule applies at the given move index.
  ## The 50-move rule states that a game is drawn if 50 moves (100 half-moves)
  ## pass without a pawn move or capture.
  ## If moveIndex is -1, checks at the current position.

  let targetIndex = game.getTargetIndex(moveIndex)
  game.positions()[targetIndex].halfmoveClock >= 100

func seventyFiveMoveRule*(game: Game, moveIndex: int = -1): bool =
  ## Check if the 75-move rule applies at the given move index (mandatory draw).
  ## The 75-move rule states that a game is automatically drawn if 75 moves (150 half-moves)
  ## pass without a pawn move or capture.
  ## If moveIndex is -1, checks at the current position.

  let targetIndex = game.getTargetIndex(moveIndex)
  game.positions()[targetIndex].halfmoveClock >= 150

func applyResult(game: var Game) =
  # Check if the game has ended and update result if it was still ongoing
  let currentPos = game.currentPosition()
  if game.result == "*":

    if currentPos.isMate():
      # Checkmate
      if currentPos.us == white:
        game.result = "0-1" # Black wins
      else:
        game.result = "1-0" # White wins
    elif currentPos.isStalemate():
      # Stalemate
      game.result = "1/2-1/2"
    elif game.fivefoldRepetition() or game.seventyFiveMoveRule():
      # Mandatory draw conditions
      game.result = "1/2-1/2"

proc newGame*(
    event: string = "?",
    site: string = "?",
    date: string = "????.??.??",
    round: string = "?",
    white: string = "?",
    black: string = "?",
    gameResult: string = "*",
    startPosition: Position = classicalStartPos,
    fen: string = "",
    annotator: string = "",
    plyCount: string = "",
    timeControl: string = "",
    time: string = "",
    termination: string = "",
    mode: string = "",
): Game =
  ## Create a new game with the Seven Tag Roster and optional additional tags.
  ## If FEN is provided, it overrides startPosition and SetUp tag is automatically added.

  result = Game()

  # Seven Tag Roster (required)
  result.headers["Event"] = event
  result.headers["Site"] = site
  result.headers["Date"] = date
  result.headers["Round"] = round
  result.headers["White"] = white
  result.headers["Black"] = black
  result.headers["Result"] = gameResult

  # Handle FEN and starting position
  if fen != "":
    result.startPosition = fen.toPosition()
    result.headers["SetUp"] = "1"
    result.headers["FEN"] = fen
  else:
    result.startPosition = startPosition
    if startPosition != classicalStartPos:
      result.headers["SetUp"] = "1"
      result.headers["FEN"] = startPosition.fen()

  result.result = gameResult

  # Optional tags (only add if provided)
  if annotator != "":
    result.headers["Annotator"] = annotator
  if plyCount != "":
    result.headers["PlyCount"] = plyCount
  if timeControl != "":
    result.headers["TimeControl"] = timeControl
  if time != "":
    result.headers["Time"] = time
  if termination != "":
    result.headers["Termination"] = termination
  if mode != "":
    result.headers["Mode"] = mode

  result.applyResult

func addMove*(game: var Game, move: Move) =
  ## Add a move to the game. Raises ValueError if the move is not legal.
  ## Updates the result if the game ends in mate or stalemate.
  let currentPos = game.currentPosition()

  if not currentPos.isLegal(move):
    raise newException(ValueError, "Move " & $move & " is not legal")

  game.moves.add(move)

  game.applyResult()



func addMove*(game: var Game, moveString: string) =
  game.addMove moveString.toMove(game.currentPosition)

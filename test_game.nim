import src/nimchess/game
import src/nimchess/strchess
import src/nimchess/movegen

# Test basic game creation
echo "Testing game creation..."
var game1 =
  newGame(event = "Test Tournament", site = "Test City", white = "Alice", black = "Bob")
echo "Game created successfully"
assert game1.headers["Event"] == "Test Tournament"
assert game1.headers["Site"] == "Test City"
assert game1.headers["White"] == "Alice"
assert game1.headers["Black"] == "Bob"
assert "SetUp" notin game1.headers
assert game1.result == "*"
echo ""

# Test adding moves
echo "Testing move addition..."
game1.addMove("e4".toMove(game1.currentPosition))
echo game1.currentPosition.fen
echo game1.currentPosition.debugString
echo "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1".toPosition.debugString
assert game1.currentPosition == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1".toPosition
echo "Added e4"
game1.addMove("e5".toMove(game1.currentPosition))
echo game1.currentPosition.fen
assert game1.currentPosition == "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2".toPosition
echo "Added e5"
assert game1.moves.len == 2
assert game1.result == "*"
echo ""

# Test illegal move
echo "Testing illegal move..."
try:
  game1.addMove("e4".toMove(game1.currentPosition)) # e4 already played
  assert false
except ValueError as e:
  echo "Caught illegal move error: ", e.msg

echo ""

# Test Scholar's mate
echo "Testing Scholar's mate..."
var mateGame = newGame()
try:
  mateGame.addMove("e4".toMove(mateGame.currentPosition))
  mateGame.addMove("e5".toMove(mateGame.currentPosition))
  mateGame.addMove("Bc4".toMove(mateGame.currentPosition))
  mateGame.addMove("Nc6".toMove(mateGame.currentPosition))
  mateGame.addMove("Qh5".toMove(mateGame.currentPosition))
  mateGame.addMove("Nf6".toMove(mateGame.currentPosition))
  mateGame.addMove("Qxf7#".toMove(mateGame.currentPosition))
  echo "Scholar's mate completed"
  echo "Final result: ", mateGame.result
  assert mateGame.currentPosition.isMate()
except Exception as e:
  echo "Error in Scholar's mate: ", e.msg

echo ""

# Test repetition detection
echo "Testing repetition detection..."
var repGame = newGame()
try:
  # Create a position that can repeat
  repGame.addMove("Nf3".toMove(repGame.currentPosition))
  repGame.addMove("Nf6".toMove(repGame.currentPosition))
  repGame.addMove("Ng1".toMove(repGame.currentPosition))
  repGame.addMove("Ng8".toMove(repGame.currentPosition))
  repGame.addMove("Nf3".toMove(repGame.currentPosition))
  repGame.addMove("Nf6".toMove(repGame.currentPosition))
  repGame.addMove("Ng1".toMove(repGame.currentPosition))
  repGame.addMove("Ng8".toMove(repGame.currentPosition))

  assert repGame.hasRepetition()
except Exception as e:
  echo "Error in repetition test: ", e.msg

echo ""

# Test FEN starting position
echo "Testing FEN starting position..."
let fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
var fenGame = newGame(fen = fen)
echo "FEN game created"
assert fenGame.headers.getOrDefault("SetUp", "not set") == "1"
assert fenGame.headers.getOrDefault("FEN", "not set") == fen

echo ""
echo "All tests completed!"

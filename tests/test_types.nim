import unittest
import nimchess
import std/[math, options, strutils]

suite "Types Tests":
  test "newSquare construction":
    check newSquare(0, 0) == a1
    check newSquare(7, 0) == h1
    check newSquare(0, 7) == a8
    check newSquare(7, 7) == h8
    check newSquare(3, 3) == d4

  test "rankNumber and fileNumber":
    check a1.rankNumber == 0
    check a8.rankNumber == 7
    check h1.rankNumber == 0
    check h8.rankNumber == 7
    check d4.rankNumber == 3

    check a1.fileNumber == 0
    check h1.fileNumber == 7
    check a8.fileNumber == 0
    check h8.fileNumber == 7
    check d4.fileNumber == 3

  test "square movement functions":
    # Test up/down
    check a1.up == a2
    check a2.down == a1
    check a8.down == a7
    check h7.up == h8

    # Test left/right
    check b1.left == a1
    check a1.right == b1
    check h1.left == g1
    check g1.right == h1

    # Test up with color
    check a1.up(white) == a2
    check a8.up(black) == a7
    check d4.up(white) == d5
    check d4.up(black) == d3

  test "edge detection":
    # Left edge
    check a1.isLeftEdge == true
    check a4.isLeftEdge == true
    check a8.isLeftEdge == true
    check b1.isLeftEdge == false
    check h1.isLeftEdge == false

    # Right edge
    check h1.isRightEdge == true
    check h4.isRightEdge == true
    check h8.isRightEdge == true
    check g1.isRightEdge == false
    check a1.isRightEdge == false

    # Upper edge
    check a8.isUpperEdge == true
    check d8.isUpperEdge == true
    check h8.isUpperEdge == true
    check a7.isUpperEdge == false
    check a1.isUpperEdge == false

    # Lower edge
    check a1.isLowerEdge == true
    check d1.isLowerEdge == true
    check h1.isLowerEdge == true
    check a2.isLowerEdge == false
    check a8.isLowerEdge == false

    # General edge detection
    check a1.isEdge == true # corner
    check h8.isEdge == true # corner
    check d1.isEdge == true # bottom edge
    check d8.isEdge == true # top edge
    check a4.isEdge == true # left edge
    check h4.isEdge == true # right edge
    check d4.isEdge == false # center

  test "mirror operations":
    # Vertical mirroring
    check a1.mirrorVertically == a8
    check a8.mirrorVertically == a1
    check h1.mirrorVertically == h8
    check h8.mirrorVertically == h1
    check d4.mirrorVertically == d5
    check d5.mirrorVertically == d4

    # Horizontal mirroring
    check a1.mirrorHorizontally == h1
    check h1.mirrorHorizontally == a1
    check a8.mirrorHorizontally == h8
    check h8.mirrorHorizontally == a8
    check d4.mirrorHorizontally == e4
    check e4.mirrorHorizontally == d4

    # Double mirroring should return original
    check a1.mirrorVertically.mirrorVertically == a1
    check a1.mirrorHorizontally.mirrorHorizontally == a1

  test "squareDistance (Chebyshev distance)":
    # Same square
    check squareDistance(a1, a1) == 0

    # Orthogonal moves
    check squareDistance(a1, a2) == 1 # one rank up
    check squareDistance(a1, b1) == 1 # one file right
    check squareDistance(a1, a8) == 7 # seven ranks up
    check squareDistance(a1, h1) == 7 # seven files right

    # Diagonal moves
    check squareDistance(a1, b2) == 1 # one diagonal
    check squareDistance(a1, c3) == 2 # two diagonals
    check squareDistance(a1, h8) == 7 # main diagonal

    # Mixed moves (L-shapes)
    check squareDistance(a1, c2) == 2 # knight-like move (max of 2 files, 1 rank)
    check squareDistance(a1, b3) == 2 # knight-like move (max of 1 file, 2 ranks)

    # Symmetric property
    check squareDistance(a1, h8) == squareDistance(h8, a1)
    check squareDistance(d4, f6) == squareDistance(f6, d4)

  test "squareManhattanDistance (Taxicab distance)":
    # Same square
    check squareManhattanDistance(a1, a1) == 0

    # Orthogonal moves
    check squareManhattanDistance(a1, a2) == 1 # one rank up
    check squareManhattanDistance(a1, b1) == 1 # one file right
    check squareManhattanDistance(a1, a8) == 7 # seven ranks up
    check squareManhattanDistance(a1, h1) == 7 # seven files right

    # Diagonal moves (sum of file and rank differences)
    check squareManhattanDistance(a1, b2) == 2 # 1 file + 1 rank
    check squareManhattanDistance(a1, c3) == 4 # 2 files + 2 ranks
    check squareManhattanDistance(a1, h8) == 14 # 7 files + 7 ranks

    # Knight moves
    check squareManhattanDistance(a1, c2) == 3 # 2 files + 1 rank
    check squareManhattanDistance(a1, b3) == 3 # 1 file + 2 ranks

    # Symmetric property
    check squareManhattanDistance(a1, h8) == squareManhattanDistance(h8, a1)
    check squareManhattanDistance(d4, f6) == squareManhattanDistance(f6, d4)

  test "Color opposite":
    check white.opposite == black
    check black.opposite == white
    check white.opposite.opposite == white
    check black.opposite.opposite == black

  test "Piece notation":
    check pawn.notation == "p"
    check knight.notation == "n"
    check bishop.notation == "b"
    check rook.notation == "r"
    check queen.notation == "q"
    check king.notation == "k"
    check noPiece.notation == "-"

  test "ColoredPiece notation":
    # White pieces (uppercase)
    check ColoredPiece(piece: pawn, color: white).notation == "P"
    check ColoredPiece(piece: knight, color: white).notation == "N"
    check ColoredPiece(piece: bishop, color: white).notation == "B"
    check ColoredPiece(piece: rook, color: white).notation == "R"
    check ColoredPiece(piece: queen, color: white).notation == "Q"
    check ColoredPiece(piece: king, color: white).notation == "K"

    # Black pieces (lowercase)
    check ColoredPiece(piece: pawn, color: black).notation == "p"
    check ColoredPiece(piece: knight, color: black).notation == "n"
    check ColoredPiece(piece: bishop, color: black).notation == "b"
    check ColoredPiece(piece: rook, color: black).notation == "r"
    check ColoredPiece(piece: queen, color: black).notation == "q"
    check ColoredPiece(piece: king, color: black).notation == "k"

    # No piece
    check ColoredPiece(piece: noPiece).notation == "-"

  test "ColoredPiece string representation":
    # Test that colored pieces have Unicode representations
    let whitePawn = ColoredPiece(piece: pawn, color: white)
    let blackPawn = ColoredPiece(piece: pawn, color: black)
    let noPieceObj = ColoredPiece(piece: noPiece)

    check whitePawn.`$` == "♟"
    check blackPawn.`$` == "♙"
    check noPieceObj.`$` == " "

    # Test other pieces have representations
    check ColoredPiece(piece: king, color: white).`$`.len > 0
    check ColoredPiece(piece: queen, color: black).`$`.len > 0

  test "toColoredPiece from character":
    # White pieces
    check 'P'.toColoredPiece == ColoredPiece(piece: pawn, color: white)
    check 'N'.toColoredPiece == ColoredPiece(piece: knight, color: white)
    check 'B'.toColoredPiece == ColoredPiece(piece: bishop, color: white)
    check 'R'.toColoredPiece == ColoredPiece(piece: rook, color: white)
    check 'Q'.toColoredPiece == ColoredPiece(piece: queen, color: white)
    check 'K'.toColoredPiece == ColoredPiece(piece: king, color: white)

    # Black pieces
    check 'p'.toColoredPiece == ColoredPiece(piece: pawn, color: black)
    check 'n'.toColoredPiece == ColoredPiece(piece: knight, color: black)
    check 'b'.toColoredPiece == ColoredPiece(piece: bishop, color: black)
    check 'r'.toColoredPiece == ColoredPiece(piece: rook, color: black)
    check 'q'.toColoredPiece == ColoredPiece(piece: queen, color: black)
    check 'k'.toColoredPiece == ColoredPiece(piece: king, color: black)

  test "toColoredPiece invalid character":
    expect(ValueError):
      discard 'x'.toColoredPiece

    expect(ValueError):
      discard '1'.toColoredPiece

  test "ZobristKey XOR assignment":
    var key1: ZobristKey = 0x123456789ABCDEF0'u64
    let key2: ZobristKey = 0xFEDCBA9876543210'u64
    let expected = key1 xor key2

    key1 ^= key2
    check key1 == expected

  test "boardString function":
    # Test with a simple function that returns some squares
    proc testSquares(square: Square): Option[string] =
      if square == a1:
        some("X")
      elif square == h8:
        some("O")
      else:
        none(string)

    let board = boardString(testSquares)

    # Should contain the expected markers
    check "X" in board
    check "O" in board
    check "|_" in board # Empty squares
    check "A B C D E F G H" in board # File labels
    check "|1" in board # Rank label for rank 1
    check "|8" in board # Rank label for rank 8

  test "distance functions relationship":
    # Chebyshev distance should always be <= Manhattan distance
    for a in a1 .. h8:
      for b in a1 .. h8:
        if a != noSquare and b != noSquare:
          let chebyshev = squareDistance(a, b)
          let manhattan = squareManhattanDistance(a, b)
          check chebyshev <= manhattan

    # For diagonal moves, Chebyshev should be much smaller
    check squareDistance(a1, h8) < squareManhattanDistance(a1, h8)

    # For orthogonal moves, they should be equal
    check squareDistance(a1, a8) == squareManhattanDistance(a1, a8)
    check squareDistance(a1, h1) == squareManhattanDistance(a1, h1)

  test "square enumeration bounds":
    # Test that noSquare is the last value
    check noSquare.ord > h8.ord

    # Test that squares are in the expected order
    check a1.ord == 0
    check h1.ord == 7
    check a2.ord == 8
    check h8.ord == 63

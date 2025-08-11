# fr  om system import int8, int32, high
import std/[math, options, strutils]
export options

#!fmt: off
type Square* = enum
  a1, b1, c1, d1, e1, f1, g1, h1,
  a2, b2, c2, d2, e2, f2, g2, h2,
  a3, b3, c3, d3, e3, f3, g3, h3,
  a4, b4, c4, d4, e4, f4, g4, h4,
  a5, b5, c5, d5, e5, f5, g5, h5,
  a6, b6, c6, d6, e6, f6, g6, h6,
  a7, b7, c7, d7, e7, f7, g7, h7,
  a8, b8, c8, d8, e8, f8, g8, h8,
  noSquare
#!fmt: on

type
  Color* = enum
    white
    black

  Piece* = enum
    pawn
    knight
    bishop
    rook
    queen
    king
    noPiece

  ColoredPiece* = object
    case piece*: Piece
    of noPiece:
      discard
    else:
      color*: Color

  ZobristKey* = uint64

func newSquare*(file: 0 .. 7, rank: 0 .. 7): Square =
  Square(rank * 8 + file)

func rankNumber*(square: Square): 0 .. 7 =
  square.int div 8

func fileNumber*(square: Square): 0 .. 7 =
  square.int mod 8

func up*(square: Square): Square =
  (square.int8 + 8).Square

func down*(square: Square): Square =
  (square.int8 - 8).Square

func left*(square: Square): Square =
  (square.int8 - 1).Square

func right*(square: Square): Square =
  (square.int8 + 1).Square

func up*(square: Square, color: Color): Square =
  if color == white: square.up else: square.down

func isLeftEdge*(square: Square): bool =
  square.int8 mod 8 == 0

func isRightEdge*(square: Square): bool =
  square.int8 mod 8 == 7

func isUpperEdge*(square: Square): bool =
  square >= a8

func isLowerEdge*(square: Square): bool =
  square <= h1

func isEdge*(square: Square): bool =
  square.isLeftEdge or square.isRightEdge or square.isUpperEdge or square.isLowerEdge

func opposite*(color: Color): Color =
  (color.uint8 xor 1).Color

func mirrorVertically*(square: Square): Square =
  (square.int8 xor 56).Square

func mirrorHorizontally*(square: Square): Square =
  (square.int8 xor 7).Square

func squareDistance*(a: Square, b: Square): int =
  ## Gets the Chebyshev distance (i.e., the number of king steps) from square a to b.
  let fileDiff = abs(a.fileNumber - b.fileNumber)
  let rankDiff = abs(a.rankNumber - b.rankNumber)
  max(fileDiff, rankDiff)

func squareManhattanDistance*(a: Square, b: Square): int =
  ## Gets the Manhattan/Taxicab distance (i.e., the number of orthogonal king steps) from square a to b.
  let fileDiff = abs(a.fileNumber - b.fileNumber)
  let rankDiff = abs(a.rankNumber - b.rankNumber)
  fileDiff + rankDiff

func `^=`*(a: var ZobristKey, b: ZobristKey) =
  a = a xor b

func boardString*(f: proc(square: Square): Option[string] {.noSideEffect.}): string =
  result = " _ _ _ _ _ _ _ _\n"
  for rank in countdown(7, 0):
    for file in 0 .. 7:
      result &= "|"
      let s = f((8 * rank + file).Square)
      if s.isSome:
        result &= s.get()
      else:
        result &= "_"
    result &= "|" & intToStr(rank + 1) & "\n"
  result &= " A B C D E F G H"

func notation*(piece: Piece): string =
  case piece
  of pawn: "p"
  of knight: "n"
  of bishop: "b"
  of rook: "r"
  of queen: "q"
  of king: "k"
  of noPiece: "-"

func notation*(coloredPiece: ColoredPiece): string =
  result = coloredPiece.piece.notation
  if coloredPiece.piece != noPiece and coloredPiece.color == white:
    result = result.toUpperAscii

func `$`*(coloredPiece: ColoredPiece): string =
  const t = [
    white: [
      pawn: "♟", knight: "♞", bishop: "♝", rook: "♜", queen: "♛", king: "♚"
    ],
    black: [
      pawn: "♙", knight: "♘", bishop: "♗", rook: "♖", queen: "♕", king: "♔"
    ],
  ]
  if coloredPiece.piece == noPiece:
    return " "
  return t[coloredPiece.color][coloredPiece.piece]

func toColoredPiece*(s: char): ColoredPiece =
  var piece: pawn .. king
  case s
  of 'P', 'p':
    piece = pawn
  of 'N', 'n':
    piece = knight
  of 'B', 'b':
    piece = bishop
  of 'R', 'r':
    piece = rook
  of 'Q', 'q':
    piece = queen
  of 'K', 'k':
    piece = king
  else:
    raise newException(ValueError, "Piece notation doesn't exist: " & s)

  let color = if s.isLowerAscii: black else: white
  ColoredPiece(color: color, piece: piece)

proc `==`*(a, b: ColoredPiece): bool =
  result = a.piece == b.piece
  if result and a.piece == noPiece:
    result = a.color == b.color

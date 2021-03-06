{-# LANGUAGE TemplateHaskell  #-}
{-# LANGUAGE DeriveAnyClass  #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE UndecidableInstances #-}
module Data.Geometry.Line.Internal where

import           Control.DeepSeq
import           Control.Lens
import qualified Data.Foldable as F
import           Data.Geometry.Point
import           Data.Geometry.Properties
import           Data.Geometry.Vector
import           Data.Ord (comparing)
import qualified Data.Traversable as T
import           Data.Vinyl
import           Data.Vinyl.CoRec
import           GHC.Generics (Generic)


--------------------------------------------------------------------------------
-- * d-dimensional Lines

-- | A line is given by an anchor point and a vector indicating the
-- direction.
data Line d r = Line { _anchorPoint :: !(Point  d r)
                     , _direction   :: !(Vector d r)
                     } deriving Generic
makeLenses ''Line

instance (Show r, Arity d) => Show (Line d r) where
  show (Line p v) = concat [ "Line (", show p, ") (", show v, ")" ]
deriving instance (Eq r,   Arity d)   => Eq            (Line d r)
deriving instance (NFData r, Arity d) => NFData        (Line d r)
deriving instance Arity d             => Functor       (Line d)
deriving instance Arity d             => F.Foldable    (Line d)
deriving instance Arity d             => T.Traversable (Line d)


type instance Dimension (Line d r) = d
type instance NumType   (Line d r) = r

-- ** Functions on lines

-- | A line may be constructed from two points.
lineThrough     :: (Num r, Arity d) => Point d r -> Point d r -> Line d r
lineThrough p q = Line p (q .-. p)

verticalLine   :: Num r => r -> Line 2 r
verticalLine x = Line (point2 x 0) (v2 0 1)

horizontalLine   :: Num r => r -> Line 2 r
horizontalLine y = Line (point2 0 y) (v2 1 0)

-- | Given a line l with anchor point p, get the line perpendicular to l that also goes through p.
perpendicularTo                           :: Num r => Line 2 r -> Line 2 r
perpendicularTo (Line p ~(Vector2 vx vy)) = Line p (v2 (-vy) vx)





-- | Test if two lines are identical, meaning; if they have exactly the same
-- anchor point and directional vector.
isIdenticalTo                         :: (Eq r, Arity d) => Line d r -> Line d r -> Bool
(Line p u) `isIdenticalTo` (Line q v) = (p,u) == (q,v)


-- | Test if the two lines are parallel.
--
-- >>> lineThrough origin (point2 1 0) `isParallelTo` lineThrough (point2 1 1) (point2 2 1)
-- True
-- >>> lineThrough origin (point2 1 0) `isParallelTo` lineThrough (point2 1 1) (point2 2 2)
-- False
isParallelTo                         :: (Eq r, Fractional r, Arity d)
                                     => Line d r -> Line d r -> Bool
(Line _ u) `isParallelTo` (Line _ v) = u `isScalarMultipleOf` v
  -- TODO: Maybe use a specialize pragma for 2D (see intersect instance for two lines.)


-- | Test if point p lies on line l
--
-- >>> origin `onLine` lineThrough origin (point2 1 0)
-- True
-- >>> point2 10 10 `onLine` lineThrough origin (point2 2 2)
-- True
-- >>> point2 10 5 `onLine` lineThrough origin (point2 2 2)
-- False
onLine                :: (Eq r, Fractional r, Arity d) => Point d r -> Line d r -> Bool
p `onLine` (Line q v) = p == q || (p .-. q) `isScalarMultipleOf` v


-- | Specific 2d version of testing if apoint lies on a line.
onLine2 :: (Ord r, Num r) => Point 2 r -> Line 2 r -> Bool
p `onLine2` (Line q v) = ccw p q (q .+^ v) == CoLinear


-- | The intersection of two lines is either: NoIntersection, a point or a line.
type instance IntersectionOf (Line 2 r) (Line 2 r) = [ NoIntersection
                                                     , Point 2 r
                                                     , Line 2 r
                                                     ]

instance (Eq r, Fractional r) => (Line 2 r) `IsIntersectableWith` (Line 2 r) where


  nonEmptyIntersection = defaultNonEmptyIntersection

  l@(Line p ~(Vector2 ux uy)) `intersect` (Line q ~v@(Vector2 vx vy))
      | areParallel = if q `onLine` l then coRec l
                                      else coRec NoIntersection
      | otherwise   = coRec r
    where
      r = q .+^ alpha *^ v

      denom       = vy * ux - vx * uy
      areParallel = denom == 0
      -- Instead of using areParallel, we can also use the generic 'isParallelTo' function
      -- for lines of arbitrary dimension, but this is a bit more efficient.

      alpha        = (ux * (py - qy) + uy * (qx - px)) / denom

      Point2 px py = p
      Point2 qx qy = q

-- | Squared distance from point p to line l
sqDistanceTo   :: (Fractional r, Arity d) => Point d r -> Line d r -> r
sqDistanceTo p = fst . sqDistanceToArg p


-- | The squared distance between the point p and the line l, and the point m
-- realizing this distance.
sqDistanceToArg              :: (Fractional r, Arity d)
                             => Point d r -> Line d r -> (r, Point d r)
sqDistanceToArg p (Line q v) = let u = q .-. p
                                   t = (-1 * (u `dot` v)) / (v `dot` v)
                                   m = q .+^ (v ^* t)
                               in (qdA m p, m)

--------------------------------------------------------------------------------
-- * Supporting Lines

-- | Types for which we can compute a supporting line, i.e. a line that contains the thing of type t.
class HasSupportingLine t where
  supportingLine :: t -> Line (Dimension t) (NumType t)

instance HasSupportingLine (Line d r) where
  supportingLine = id

--------------------------------------------------------------------------------
-- * Convenience functions on Two dimensional lines

-- | Create a line from the linear function ax + b
fromLinearFunction     :: Num r => r -> r -> Line 2 r
fromLinearFunction a b = Line (point2 0 b) (v2 1 a)

-- | get values a,b s.t. the input line is described by y = ax + b.
-- returns Nothing if the line is vertical
toLinearFunction                             :: forall r. (Fractional r, Eq r)
                                             => Line 2 r -> Maybe (r,r)
toLinearFunction l@(Line _ ~(Vector2 vx vy)) = match (l `intersect` verticalLine (0 :: r)) $
       (H $ \NoIntersection -> Nothing)    -- l is a vertical line
    :& (H $ \(Point2 _ b)   -> Just (vy / vx,b))
    :& (H $ \_              -> Nothing)    -- l is a vertical line (through x=0)
    :& RNil

-- | Result of a side test
data SideTest = Below | On | Above deriving (Show,Read,Eq,Ord)

-- | Given a point q and a line l, compute to which side of l q lies. For
-- vertical lines the left side of the line is interpeted as below.
--
-- >>> point2 10 10 `onSide` (lineThrough origin $ point2 10 5)
-- Above
-- >>> point2 10 10 `onSide` (lineThrough origin $ point2 (-10) 5)
-- Above
-- >>> point2 5 5 `onSide` (verticalLine 10)
-- Below
-- >>> point2 5 5 `onSide` (lineThrough origin $ point2 (-3) (-3))
-- On
onSide                :: (Ord r, Num r) => Point 2 r -> Line 2 r -> SideTest
q `onSide` (Line p v) = let r    =  p .+^ v
                            f z         = (z^.xCoord, -z^.yCoord)
                            minBy g a b = F.minimumBy (comparing g) [a,b]
                            maxBy g a b = F.maximumBy (comparing g) [a,b]
                        in case ccw (minBy f p r) (maxBy f p r) q of
                          CCW      -> Above
                          CW       -> Below
                          CoLinear -> On



-- | Test if the query point q lies (strictly) above line l
liesAbove       :: (Ord r, Num r) => Point 2 r -> Line 2 r -> Bool
q `liesAbove` l = q `onSide` l == Above


-- | Get the bisector between two points
bisector     :: Fractional r => Point 2 r -> Point 2 r -> Line 2 r
bisector p q = let v = q .-. p
                   h = p .+^ (v ^/ 2)
               in perpendicularTo (Line h v)


-- | Compares the lines on slope. Vertical lines are considered larger than
-- anything else.
--
-- >>> (Line origin (Vector2 5 1)) `cmpSlope` (Line origin (Vector2 3 3))
-- LT
-- >>> (Line origin (Vector2 5 1)) `cmpSlope` (Line origin (Vector2 (-3) 3))
-- GT
-- >>> (Line origin (Vector2 5 1)) `cmpSlope` (Line origin (Vector2 0 1))
-- LT
cmpSlope :: (Num r, Ord r) => Line 2 r -> Line 2 r -> Ordering
(Line _ u) `cmpSlope` (Line _ v) = case ccw origin (f u) (f v) of
                                     CCW      -> LT
                                     CW       -> GT
                                     CoLinear -> EQ
  where
    f w@(Vector2 x y) = Point $ case (x `compare` 0, y >= 0) of
                                  (GT,_)    -> w
                                  (EQ,True) -> w
                                  _         -> (-1) *^ w
                                  -- x < 0, or (x==0 and y <0 ; i.e. a vertical line)

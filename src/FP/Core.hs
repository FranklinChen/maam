module FP.Core 

-- Exports {{{

  ( module Prelude
  , module FP.Core
  , module GHC.Exts
  , module Data.Set
  , module Data.Map
  ) where

-- }}}

-- Imports {{{

import qualified Prelude
import Prelude 
  ( Eq(..), Ord(..)
  , (.), ($), const, flip, curry, uncurry
  , Bool(..), (||), (&&), not, otherwise
  , Char, Int, Integer, Double, Rational
  , Maybe(..)
  , error, undefined, seq
  , IO
  )
import Data.ByteString.Char8 (ByteString)
import GHC.Exts (type Constraint)
import qualified Data.ByteString.Char8 as BS
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Map as Map
import Data.Map (Map)

-- }}}

-- Precedence {{{

infixl 9 #
infixl 9 #!
infixl 9 <@>
infixr 9 <.>
infixr 9 *.
infixr 9 *.~

infix 7 /
infix 7 //
infixr 7 *
infixr 7 <*>
infixr 7 /\

infix 6 -
infix 6 \-\
infixr 6 +
infixr 6 ++
infixr 6 <+>
infixr 6 <+>~
infixr 6 \/

infix 4 <~
infix 4 <.
infix 4 ?

infixl 1 >>=
infixl 1 >>=~
infixl 1 >>
infixl 1 >>~

infixr 0 *$
infixr 0 *$~
infixr 0 <$>
infixr 0 <$~>
infixr 0 <*$>

-- }}}

-------------
-- Classes --
-------------

-- Category {{{ --

class Category t where
  id :: t a a
  (<.>) :: t b c -> t a b -> t a c

-- }}} --

-- Monoid {{{

class Monoid a where
  null :: a
  (++) :: a -> a -> a

-- }}}

-- Conversion {{{

class ToInteger a where
  toInteger :: a -> Integer
class FromInteger a where
  fromInteger :: Integer -> a

class ToRational a where
  toRational :: a -> Rational
class FromRational a where
  fromRational :: Rational -> a

class ToDouble a where
  toDouble :: a -> Double
class FromDouble a where
  fromDouble :: Double -> a

class FromChars a where
  fromChars :: Chars -> a
class ToChars a where
  toChars :: a -> Chars
-- for Overlaoded Strings extension
fromString :: Chars -> String
fromString = fromChars

class ToString t where
  toString :: t -> String

-- }}}

-- Arithmetic {{{ --

class Peano a where
  pzero :: a
  psuc :: a -> a
class Additive a where
  zero :: a
  (+) :: a -> a -> a
class (Additive a) => Subtractive a where
  (-) :: a -> a -> a
class (Additive a) => Multiplicative a where
  one :: a
  (*) :: a -> a -> a
class (Multiplicative a) => Divisible a where
  (/) :: a -> a -> a
class (Multiplicative a) => TruncateDivisible a where
  (//) :: a -> a -> a

negate :: (Subtractive a) => a -> a
negate x = zero - x

inverse :: (Divisible a) => a -> a
inverse x = one / x

class (Peano a, TruncateDivisible a, FromInteger a, ToInteger a) => Integral a where
class (Peano a, Divisible a, FromInteger a, FromDouble a, ToDouble a) => Floating a where

-- }}}

-- PartialOrder {{{

data POrdering = PEQ | PLT | PGT | PUN

class PartialOrder a where
  pcompare :: a -> a -> POrdering
  pcompare x y = case (x <~ y, y <~ x) of
    (True , True ) -> PEQ
    (True , False) -> PLT
    (False, True ) -> PGT
    (False, False) -> PUN
  (<~) :: a -> a -> Bool
  x <~ y = case pcompare x y of
    PLT -> True
    PEQ -> True
    _   -> False
  (<.) :: a -> a -> Bool
  x <. y = case pcompare x y of
    PLT -> True
    _ -> False

class PartialOrderF t where
  partialOrderF :: (PartialOrder a) => W (PartialOrder (t a))

discreteOrder :: (Eq a) => a -> a -> POrdering
discreteOrder x y = if x == y then PEQ else PUN

poiter :: (PartialOrder a) => (a -> a) -> a -> a
poiter f = loop
  where
    loop x =
      let x' = f x
      in if x' <~ x then x else loop x'

-- }}}

-- Lattice {{{ --

class JoinLattice a where
  bot :: a
  (\/) :: a -> a -> a

joins :: (Iterable a t, JoinLattice a) => t -> a
joins = iter (\/) bot

collect :: (JoinLattice a, PartialOrder a) =>  (a -> a) -> a -> a
collect f = poiter $ \ x -> x \/ f x

class MeetLattice a where
  top :: a
  (/\) :: a -> a -> a

class (JoinLattice a, MeetLattice a) => Lattice a where

-- }}} --

-- Negatable{{{ 

class Dual a where
  dual :: a -> a

-- }}}

-- Universal{{{ 

class Universal a where
instance Universal a

-- }}}

-- Iterable {{{

class Iterable a t | t -> a where
  iter :: (a -> b -> b) -> b -> t -> b

iterOn :: (Iterable a t) => t -> b -> (a -> b -> b) -> b
iterOn = mirror iter

traverse :: (Iterable a t, Monad m) => (a -> m ()) -> t -> m ()
traverse f = iter (\ a m -> m >> f a) $ return ()

traverseOn :: (Iterable a t, Monad m) => t -> (a -> m ()) -> m ()
traverseOn = flip traverse

class CoIterable a t | t -> a where
  coiter :: (a -> b -> b) -> b -> t -> b

-- }}}

-- Functorial {{{

class Functorial c t where
  functorial :: (c a) => W (c (t a))

class Bifunctorial c t where
  bifunctorial :: (c a, c b) => W (c (t a b))

bifunctorialP :: (Bifunctorial c t, c a, c b) => P c -> P t -> P a -> P b -> W (c (t a b))
bifunctorialP P P P P = bifunctorial

-- }}}

-- MapLike {{{

class (Indexed k v t, Iterable (k, v) t) => MapLike k v t | t -> k, t -> v where
  pempty :: t
  psingleton :: k -> v -> t
  punionWith :: (v -> v -> v) -> t -> t -> t
  pintersectionWith :: (v -> v -> v) -> t -> t -> t
  pmodify :: (v -> v) -> k -> t -> t
  psize :: (Integral n) => t -> n

pinsertWith :: (MapLike k v t) => (v -> v -> v) -> k -> v -> t -> t
pinsertWith f k v = punionWith f (psingleton k v)

pinsert :: (MapLike k v t) => k -> v -> t -> t
pinsert = pinsertWith $ const id

ponlyKeys :: (Iterable k t, MapLike k v u) => t -> u -> u
ponlyKeys t u = iter (\ k -> maybe id (pinsert k) $ u # k) pempty t

-- }}}

-- SetLike {{{

class (Iterable e t) => SetLike e t | t -> e where
  sempty :: t
  ssingleton :: e -> t
  sunion :: t -> t -> t
  sintersection :: t -> t -> t
  (\-\) :: t -> t -> t
  (?) :: t -> e -> Bool
  ssize :: (Integral n) => t -> n

sunionMap :: (Iterable a t, SetLike b u) => (a -> u) -> t -> u
sunionMap f = iter (sunion . f) sempty

seachUnion :: (Iterable a t, SetLike b u) => t -> (a -> u) -> u
seachUnion = flip sunionMap

-- }}}

-- Indexed {{{

class Indexed i e t | t -> i, t -> e where
  (#) :: t -> i -> Maybe e
  (#!) :: t -> i -> e
  (#!) = unsafeCoerceJust .: (#)

index :: (Indexed i e t) => t -> i -> Maybe e
index = (#)

lookup :: (Indexed i e t) => i -> t -> Maybe e
lookup = flip (#)

-- }}}

-- Functor {{{

class Functor t where
  map :: (a -> b) -> t a -> t b

(<$>) :: (Functor t) => (a -> b) -> t a -> t b
(<$>) = map

class FunctorM t where
  mapM :: (Monad m) => (a -> m b) -> t a -> m (t b)

(<*$>) :: (FunctorM t, Monad m) => (a -> m b) -> t a -> m (t b)
(<*$>) = mapM

eachM :: (FunctorM t, Monad m) => t a -> (a -> m b) -> m (t b)
eachM = flip mapM

class CFunctor c t | t -> c where
  cmap :: (c a, c b) => (a -> b) -> t a -> t b

(<$~>) :: (CFunctor c t, c a, c b) => (a -> b) -> t a -> t b
(<$~>) = cmap

-- }}}

-- Applicative {{{

class (Unit t, Functor t) => Applicative t where
  (<*>) :: t a -> t b -> t (a, b)
  aT <*> bT = unit (,) <@> aT <@> bT
  (<@>) :: t (a -> b) -> t a -> t b
  fT <@> aT = map (uncurry ($)) $ fT <*> aT

-- }}}

-- Monad {{{

class Unit t where
  unit :: a -> t a

class (Functor m, Applicative m) => Monad m where
  (>>=) :: m a -> (a -> m b) -> m b

return :: (Monad m) => a -> m a
return = unit

(>>) :: (Monad m) => m a -> m b -> m b
aM >> bM = aM >>= const bM

extend :: (Monad m) => (a -> m b) -> (m a -> m b)
extend = flip (>>=)

(*$) :: (Monad m) => (a -> m b) -> (m a -> m b)
(*$) = extend

(*.) :: (Monad m) => (b -> m c) -> (a -> m b) -> (a -> m c)
(g *. f) x = g *$ f x

mmap :: (Monad m) => (a -> b) -> m a -> m b
mmap f aM = do
  a <- aM
  return $ f a

mpair :: (Monad m) => m a -> m b -> m (a, b)
mpair aM bM = do
  a <- aM
  b <- bM
  return (a, b)

mapply :: (Monad m) => m (a -> b) -> m a -> m b
mapply fM aM = do
  f <- fM
  a <- aM
  return $ f a

class CUnit c t | t -> c where
  cunit :: (c a) => a -> t a

class (CUnit c m) => CMonad c m | m -> c where
  (>>=~) :: (c a, c b) => m a -> (a -> m b) -> m b

creturn :: (CMonad c m, c a) => a -> m a
creturn = cunit

(>>~) :: (CMonad c m, c a, c b) => m a -> m b -> m b
aM >>~ bM = aM >>=~ \ _ -> bM

cextend :: (CMonad c m, c a, c b) => (a -> m b) -> (m a -> m b)
cextend = flip (>>=~)

(*$~) :: (CMonad c m, c a, c b) => (a -> m b) -> (m a -> m b)
(*$~) = cextend

(*.~) :: (CMonad c m, c a, c b, c d) => (b -> m d) -> (a -> m b) -> (a -> m d)
(g *.~ f) x = g *$~ f x

cmmap :: (CMonad c m) => (c a, c b) => (a -> b) -> m a -> m b
cmmap f aM =
  aM >>=~ \ a ->
  creturn $ f a

class (Monad m) => MonadFail m where
  fail :: Chars -> m a

class (CMonad c m) => CMonadFail c m | m -> c where
  cfail :: (c a) => Chars -> m a

class (Monad m) => MonadZero m where
  mzero :: m a

class (CMonad c m) => CMonadZero c m where
  cmzero :: (c a) => m a

class (Monad m) => MonadPlus m where
  (<+>) :: m a -> m a -> m a

msum :: (Iterable a t, MonadZero m, MonadPlus m) => t -> m a
msum = iter ((<+>) . return) mzero

msums :: (Iterable (m a) t, MonadZero m, MonadPlus m) => t -> m a
msums = iter (<+>) mzero

class (CMonad c m) => CMonadPlus c m | m -> c where
  (<+>~) :: (c a) => m a -> m a -> m a

cmsum :: (Iterable a t, MonadZero m, CMonadPlus c m) => (c a) => t -> m a
cmsum = iter ((<+>~) . creturn) mzero

type m ~> n = forall a. m a -> n a
type (m ~>~ n) c = forall a. (c a) => m a -> n a

-- }}}

-- MonadMaybe {{{

newtype MaybeT m a = MaybeT { runMaybeT :: m (Maybe a) }
class (Monad m) => MonadMaybeI m where
  maybeI :: m ~> MaybeT m
class (Monad m) => MonadMaybeE m where
  maybeE :: MaybeT m ~> m
class (MonadMaybeI m, MonadMaybeE m) => MonadMaybe m where

useMaybeM :: (MonadMaybeE m) => m (Maybe a) -> m a
useMaybeM = maybeE . MaybeT

useMaybe :: (MonadMaybeE m) => Maybe a -> m a
useMaybe = useMaybeM . return

useMaybeZero :: (MonadZero m) => Maybe a -> m a
useMaybeZero Nothing = mzero
useMaybeZero (Just x) = return x

-- }}}

-- MonadState {{{

newtype StateT s m a = StateT { unStateT :: s -> m (a, s) }

class (Monad m) => MonadStateI s m where
  stateI :: m ~> StateT s m
class (Monad m) => MonadStateE s m where
  stateE :: StateT s m ~> m
class (MonadStateI s m, MonadStateE s m) => MonadState s m where

get :: (MonadStateE s m) => m s
get = stateE $ StateT $ \ s -> return (s, s)

getP :: (MonadStateE s m) => P s -> m s
getP P = get

getL :: (MonadStateE s m) => Lens s a -> m a
getL l = mmap (access l) get

put :: (MonadStateE s m) => s -> m ()
put s = stateE $ StateT $ \ _ -> return ((), s)

putP :: (MonadStateE s m) => P s -> s -> m ()
putP P = put

putL :: (MonadStateE s m) => Lens s a -> a -> m ()
putL = modify .: set

modify :: (MonadStateE s m) => (s -> s) -> m ()
modify f = stateE $ StateT $ \ s -> return ((), f s)

modifyP :: (MonadStateE s m) => P s -> (s -> s) -> m ()
modifyP P = modify

modifyL :: (MonadStateE s m) => Lens s a -> (a -> a) -> m ()
modifyL = modify .: update

class (CMonad c m) => CMonadStateI c s m | m -> c where
  cstateI :: (m ~>~ StateT s m) c
class (CMonad c m) => CMonadStateE c s m | m -> c where
  cstateE :: (StateT s m ~>~ m) c
class (CMonadStateI c s m, CMonadStateE c s m) => CMonadState c s m | m -> c where

cget :: (CMonadStateE c s m, c s, c (s, s)) => m s
cget = cstateE $ StateT $ \ s -> creturn (s, s)

cgetP :: (CMonadStateE c s m, c s, c (s, s)) => P s -> m s
cgetP P = cget

cgetL :: (CMonadStateE c s m, c s, c (s, s), c a) => Lens s a -> m a
cgetL l = cmmap (access l) cget

cput :: (CMonadStateE c s m, c (), c ((), s)) => s -> m ()
cput s = cstateE $ StateT $ \ _ -> creturn ((), s)

cputP :: (CMonadStateE c s m, c (), c ((), s)) => P s -> s -> m ()
cputP P = cput

cputL :: (CMonadStateE c s m, c (), c ((), s)) => Lens s a -> a -> m ()
cputL = cmodify .: set

cmodify :: (CMonadStateE c s m, c (), c ((), s)) => (s -> s) -> m ()
cmodify f = cstateE $ StateT $ \ s -> creturn ((), f s)

cmodifyP :: (CMonadStateE c s m, c (), c ((), s)) => P s -> (s -> s) -> m ()
cmodifyP P = cmodify

cmodifyL :: (CMonadStateE c s m, c (), c ((), s)) => Lens s a -> (a -> a) -> m ()
cmodifyL = cmodify .: update

-- }}}

----------
-- Data --
----------

-- Function {{{ --

instance Category (->) where
  id x = x
  (<.>) g f x = g (f x)
instance Functor ((->) a) where
  map = (.)
instance (JoinLattice b) => JoinLattice (a -> b) where
  bot = const bot
  (\/) f g x = f x \/ g x
instance (MeetLattice b) => MeetLattice (a -> b) where
  top = const top
  (/\) f g x = f x /\ g x
instance (Lattice b) => Lattice (a -> b) where

applyTo :: a -> (a -> b) -> b
applyTo = flip ($)

(.:) :: (c -> d) -> (a -> b -> c) -> (a -> b -> d)
(.:) = (.) . (.)

rotateR :: (a -> b -> c -> d) -> (c -> a -> b -> d)
rotateR f c a b = f a b c

rotateL :: (a -> b -> c -> d) -> (b -> c -> a -> d)
rotateL f b c a = f a b c

mirror :: (a -> b -> c -> d) -> (c -> b -> a -> d)
mirror f c b a = f a b c

-- }}} --

-- Tuple {{{

mapFst :: (a -> c) -> (a, b) -> (c, b)
mapFst f (a, b) = (f a, b)

mapSnd :: (b -> c) -> (a, b) -> (a, c)
mapSnd f (a, b) = (a, f b)

-- }}}

-- Bool {{{ --

instance JoinLattice Bool where
  bot = False
  (\/) = (||)
instance MeetLattice Bool where
  top = True
  (/\) = (&&)
instance Dual Bool where
  dual = not

ifThenElse :: Bool -> a -> a -> a
ifThenElse True  x _ = x
ifThenElse False _ y = y

-- }}} --

-- Sum {{{

data a :+: b = Inl a | Inr b

-- }}}

-- P {{{

data P a = P

-- }}}

-- Pointed {{{

data Pointed a = Top | Bot | Point a

instance (Eq a) => JoinLattice (Pointed a) where
  bot = Bot
  Top     \/ _   = Top
  _       \/ Top = Top
  Bot     \/ p   = p
  p       \/ Bot = p
  Point x \/ Point y 
    | x == y = Point x
    | otherwise = Top

-- }}}

-- String {{{

type String = ByteString
type Chars = [Char]

instance ToChars String where
  toChars = BS.unpack
instance FromChars String where
  fromChars = BS.pack

-- }}}

-- W {{{

data W (c :: Constraint) where
  W :: (c) => W c

with :: W c -> (c => a) -> a
with W x = x

-- }}}

-- Maybe {{{

instance Unit Maybe where
  unit = Just
instance Monad Maybe where
  Nothing >>= _ = Nothing
  Just x >>= k = k x
instance Applicative Maybe where (<@>) = mapply
instance Functor Maybe where map = mmap

unsafeCoerceJust :: Maybe a -> a
unsafeCoerceJust (Just a) = a
unsafeCoerceJust Nothing = error $ toChars "expected Just but found Nothing"

maybe :: b -> (a -> b) -> Maybe a -> b
maybe i _ Nothing = i
maybe _ f (Just a) = f a

-- }}}

-- ID {{{

newtype ID a = ID { runID :: a }

instance Unit ID where
  unit = ID
instance Monad ID where
  ID x >>= k = k x
instance Applicative ID where (<@>) = mapply 
instance Functor ID where map = mmap
 

-- }}}

-- Set {{{

instance Iterable a (Set a) where
  iter = Set.foldl' . flip
instance (Ord a) => SetLike a (Set a) where
  sempty = Set.empty
  ssingleton = Set.singleton
  sunion = Set.union
  (\-\) = (Set.\\)
  sintersection = Set.intersection
  (?) = flip Set.member
  ssize = fromInteger . toInteger . Set.size
instance CUnit Ord Set where
  cunit = ssingleton
instance CMonad Ord Set where
  (>>=~) = seachUnion
instance CFunctor Ord Set where
  cmap = Set.map
instance (Ord a) => PartialOrder (Set a) where
  (<~) = Set.isSubsetOf
instance (Ord a) => JoinLattice (Set a) where
  bot = sempty
  (\/) = sunion

smember :: (SetLike a t) => a -> t -> Bool
smember = flip (?)

sinsert :: (SetLike a t) => a -> t -> t
sinsert = sunion . ssingleton

smap :: (Iterable a t, SetLike b u) => (a -> b) -> t -> u
smap f = iter (sinsert . f) sempty

useMaybeSet :: (SetLike a t) => Maybe a -> t
useMaybeSet Nothing = sempty
useMaybeSet (Just a) = ssingleton a

sset :: (Iterable a t, SetLike a u) => t -> u
sset = iter sinsert sempty

-- }}}

-- Map {{{

instance Iterable (k, v) (Map k v) where
  iter f = Map.foldlWithKey $ \ b k v -> f (k, v) b
instance (Ord k) => Indexed k v (Map k v) where
  p # k = Map.lookup k p
  
instance (Ord k) => MapLike k v (Map k v) where
  pempty = Map.empty
  psingleton = Map.singleton
  punionWith = Map.unionWith
  pintersectionWith = Map.intersectionWith
  pmodify = Map.adjust
  psize = fromInteger . toInteger . Map.size

-- }}}

-- Int {{{

instance FromInteger Int where
  fromInteger = Prelude.fromIntegral
instance ToInteger Int where
  toInteger = Prelude.toInteger
instance Peano Int where
  pzero = 0
  psuc = Prelude.succ
instance Additive Int where
  zero = 0
  (+) = (Prelude.+)
instance Multiplicative Int where
  one = 1
  (*) = (Prelude.*)
instance TruncateDivisible Int where
  (//) = Prelude.div
instance Integral Int where

-- }}}

-- Integer {{{

instance FromInteger Integer where
  fromInteger = id
instance ToInteger Integer where
  toInteger = id
instance Additive Integer where
  zero = 0
  (+) = (Prelude.+)
instance Subtractive Integer where
  (-) = (Prelude.-)

-- }}}

-- IO {{{

print :: String -> IO ()
print = Prelude.putStrLn . toChars

-- }}}

-- Lens {{{ --

data Cursor a b = Cursor { focus :: a, construct :: a -> b }

data Lens a b = Lens { runLens :: a -> Cursor b a }

lens :: (a -> b) -> (a -> b -> a) -> Lens a b
lens getter setter = Lens $ \ s -> Cursor (getter s) (setter s)

isoLens :: (a -> b) -> (b -> a) -> Lens a b
isoLens to from = lens to $ const from

instance Category Lens where
  id = Lens $ \ a -> Cursor a id
  g <.> f = Lens $ \ a -> 
    let Cursor b ba = runLens f a
        Cursor c cb = runLens g b
    in Cursor c $ ba . cb

access :: Lens a b -> a -> b
access = focus .: runLens

update :: Lens a b -> (b -> b) -> a -> a
update l f a =
  let Cursor b ba = runLens l a
  in ba $ f b
(~:) :: Lens a b -> (b -> b) -> a -> a
(~:) = update

udpateM :: (Monad m) => Lens a b -> (b -> m b) -> a -> m a
udpateM l f a =
  let Cursor b ba = runLens l a
  in mmap ba $ f b

set :: Lens a b -> b -> a -> a
set l = update l . const
(=:) :: Lens a b -> b -> a -> a
(=:) = set

(|:) :: a -> (a -> a) -> a
(|:) = applyTo

-- }}} --

-- List {{{

instance Functor [] where
  map _ [] = []
  map f (x:xs) = f x:map f xs
instance FunctorM [] where
  mapM _ [] = return []
  mapM f (x:xs) = do
    y <- f x
    ys <- mapM f xs
    return $ y:ys
instance Iterable a [a] where
  iter _ i [] = i
  iter f i (x:xs) = let i' = f x i in i' `seq` iter f i' xs
instance CoIterable a [a] where
  coiter _ i [] = i
  coiter f i (x:xs) = f x $ coiter f i xs
instance Monoid [a] where
  null = []
  (++) = (Prelude.++)
instance Unit [] where
  unit = (:[])
instance MonadPlus [] where
  (<+>) = (++)
instance Monad [] where
  []     >>= _ = []
  (x:xs) >>= k = k x ++ (xs >>= k)
instance Applicative [] where
  []     <*> _  = []
  (x:xs) <*> ys = map (x,) ys ++ xs <*> ys

singleton :: a -> [a]
singleton = (:[])

zip :: [a] -> [b] -> [(a, b)]
zip [] _ = []
zip _ [] = []
zip (x:xs) (y:ys) = (x,y):zip xs ys

zipSameLength :: [a] -> [b] -> Maybe [(a, b)]
zipSameLength [] [] = Just []
zipSameLength [] (_:_) = Nothing
zipSameLength (_:_) [] = Nothing
zipSameLength (x:xs) (y:ys) = do
  xys <- zipSameLength xs ys
  return $ (x, y):xys

firstN :: (Eq n, Integral n) => n -> [a] -> [a]
firstN n = loop zero
  where
    loop _ [] = []
    loop i (x:xs) | i == n = []
                  | otherwise = x:loop (psuc i) xs

-- }}}

-- ListSet {{{

newtype ListSet a = ListSet { runListSet :: [a] }
  deriving (Unit, Functor, Applicative, Monad, MonadPlus, Iterable a)
instance JoinLattice (ListSet a) where
  bot = ListSet []
  xs1 \/ xs2 = ListSet $ runListSet xs1 ++ runListSet xs2

-- }}}

-- StateT {{{ --

instance (Unit m) => Unit (StateT s m) where
  unit x = StateT $ \ s -> unit (x, s)
instance (Functor m) => Functor (StateT s m) where
  map f aM = StateT $ \ s -> map (mapFst f) (unStateT aM s)
instance (Applicative m) => Applicative (StateT s m) where
  aM <*> bM = StateT $ \ s -> map (\ ((a, _), (b, s')) -> ((a, b), s')) $ 
    unStateT aM s <*> unStateT bM s
instance (Monad m) => Monad (StateT s m) where
  aM >>= k = StateT $ \ s -> do
    (a, s') <- unStateT aM s
    unStateT (k a) s'

instance (Monad m) => MonadStateI s (StateT s m) where
  stateI aM = StateT $ \ s -> StateT $ \ s' -> do
    as' <- unStateT aM s
    return (as', s')
instance (Monad m) => MonadStateE s (StateT s m) where
  stateE aMM = StateT $ \ s -> do
    (as', _) <- unStateT (unStateT aMM s) s
    return as'
-- PROOF of: stateE . stateI = id {{{
-- 
-- stateE . stateI = id
-- <->
-- (\ aMM -> StateT $ \ s -> do { (as', _) <- unStateT (unStateT aMM s) s ; return as') 
-- .
-- (\ aM -> StateT $ \ s -> StateT $ \ s' -> do { as' <- unStateT aM s ; return (as', s')})
-- = 
-- id
-- <->
-- aM
-- =
-- StateT $ \ s -> do { (as', _) <- unStateT (unStateT (StateT $ \ s -> StateT $ \ s' -> do { as' <- unStateT aM s ; return (as', s')}) s) s ; return as'
-- = [[StateT and function beta]] 
-- StateT $ \ s -> do { (as', _) <- unStateT (StateT $ \ s' -> do { as' <- unStaetT aM s ; return (as', s')}) s ; return as'
-- = [[StateT and function beta]]
-- StateT $ \ s -> do { (as', s') <- do { as' <- unStateT aM s ; return (as', s)} ; return as'
-- = [[monad associativity]]
-- StateT $ \ s -> do
--   as' <- unStateT aM s
--   (as', s') <- return (as', s)
--   return as'
-- = [[bind left unit]]
--   StateT $ \ s -> do
--     as' <- unStateT aM s
--     return as'
-- = [[bind right unit]]
--   StateT $ \ s -> do
--     unStateT aM s
-- = [[StateT and function eta]]
-- aM
-- QED }}}

instance (MonadZero m) => MonadZero (StateT s m) where
  mzero = StateT $ const mzero
instance (MonadPlus m) => MonadPlus (StateT s m) where
  aM1 <+> aM2 = StateT $ \ s -> unStateT aM1 s <+> unStateT aM2 s

-- }}} --

-- ListT {{{

newtype ListT m a = ListT { runListT :: m (ListSet a) }

instance (Unit m) => Unit (ListT m) where
  unit = ListT . unit . ListSet . singleton
instance (Functor m) => Functor (ListT m) where
  map f aM = ListT $ map (map f) $ runListT aM
instance (Monad m, Functorial JoinLattice m) => Applicative (ListT m) where
  (<*>) = mpair
instance (Monad m, Functorial JoinLattice m) => Monad (ListT m) where
  (>>=) :: forall a b. ListT m a -> (a -> ListT m b) -> ListT m b
  aM >>= k = ListT $ do
    xs <- runListT aM
    runListT $ msums $ map k xs
instance (Monad m, Functorial JoinLattice m) => MonadZero (ListT m) where
  mzero :: forall a. ListT m a
  mzero = 
    with (functorial :: W (JoinLattice (m (ListSet a)))) $
    ListT bot
instance (Monad m, Functorial JoinLattice m) => MonadPlus (ListT m) where
  (<+>) :: forall a. ListT m a -> ListT m a -> ListT m a
  aM1 <+> aM2 = 
    with (functorial :: W (JoinLattice (m (ListSet a)))) $
    ListT $ runListT aM1 \/ runListT aM2

-- PROOF of: associativity, commutativity and unit of <+> for (ListT m) {{{
--
-- Follows trivially from definition and Lattice laws for underlying monad.
-- QED }}}

-- PROOF of: monad laws for (ListT m) {{{
--
-- ASSUMPTION 1: returnₘ a <+> returnₘ b = returnₘ (a \/ b)
-- [this comes from m being a lattice functor. (1 x + 1 y) = 1 (x + y)]
--
-- * PROOF of: left unit := return x >>= k = k x {{{
--   
--   return x >>= k
--   = [[definition of >>=]]
--   ListT $ do { xs <- runListT $ return x ; runListT $ msums $ map k xs }
--   = [[definition of return]]
--   ListT $ do { xs <- runListT $ ListT $ return [x] ; runListT $ msums $ map k xs }
--   = [[ListT beta]]
--   ListT $ do { xs <- return [x] ; runListT $ msums $ map k xs }
--   = [[monad left unit]]
--   ListT $ runListT $ msums $ map k [x]
--   = [[definition of map]]
--   ListT $ runListT $ msums $ [k x]
--   = [[definition of msums and <+> unit]]
--   ListT $ runListT $ k x
--   = [[ListT eta]]
--   k x
--   QED }}}
--
-- * PROOF of: right unit := aM >>= return = aM {{{
--
--   aM >>= return
--   = [[definition of >>=]]
--   ListT $ { xs <- runListT aM ; runListT $ msums $ map return xs }
--   = [[induction/expansion on xs]]
--   ListT $ { [x1,..,xn] <- runListT aM ; runListT $ msums $ map return [x1,..,xn] }
--   = [[definition of return and map]]
--   ListT $ { [x1,..,xn] <- runListT aM ; runListT $ msums $ [ListT $ return [x1],..,ListT $ return [xn]] }
--   = [[definition of msums]]
--   ListT $ { [x1,..,xn] <- runListT aM ; runListT $ ListT $ return [x1] <+> .. <+> return [xn] }
--   = [[assumption 1]]
--   ListT $ { [x1,..,xn] <- runListT aM ; runListT $ ListT $ return [x1,..,xn] }
--   = [[ListT beta]]
--   ListT $ { [x1,..,xn] <- runListT aM ; return [x1,..,xn] }
--   = [[monad right unit]]
--   ListT $ runListT aM
--   = [[ListT eta]]
--   aM
--   QED }}}
--
-- * PROOF of: associativity := (aM >>= k1) >>= k2 = { x <- aM ; k1 x >>= k2 } {{{
--
--   (aM >>= k1) >>= k2
--   = [[definition of >>=]]
--   ListT $ { xs <- runListT $ ListT $ { xs' <- runListT aM ; runListT $ msums $ map k1 xs' } ; runListT $ msums $ map k xs }
--   = [[ListT beta]]
--   ListT $ { xs <- { xs' <- runListT aM ; runListT $ msums $ map k1 xs' } ; runListT $ msums $ map k xs }
--   = [[monad associativity]]
--   ListT $ { xs' <- runListT aM ; xs <- runListT $ msums $ map k1 xs' ; runListT $ msums $ map k xs }
--   =
--   LHS
--
--   { x <- aM ; k1 x >>= k2 }
--   = [[definition of >>=]]
--   ListT $ { xs' <- runListT aM ; runListT $ msums $ map (\ x -> ListT $ { xs <- runListT (k1 x) ; runListT $ msums $ map k2 xs }) xs' }
--   = [[induction/expansion on xs']]
--   ListT $ { [x1,..,xn] <- runListT aM ; runListT $ msums $ map (\ x -> ListT $ { xs <- runListT (k1 x) ; runListT $ msums $ map k2 xs }) [x1,..,xn] }
--   = [[definition of map]]
--   ListT $ { [x1,..,xn] <- runListT aM ; runListT $ msums $ [ListT $ { xs <- runListT (k1 x1) ; runListT $ msums $ map k2 xs },..,ListT $ { xs <- runListT (k1 xn) ; runList $ msums $ map k2 xs}] }
--   = [[definition of msum]]
--   ListT $ { [x1,..,xn] <- runListT aM ; runListT $ ListT { xs <- runListT (k1 x1) ; runListT $ msums $ map k2 xs } <+> .. <+> ListT { xs <- runListT (k1 xn) ; runListT $ msums $ map k2 xs } }
--   = [[ListT beta and definition of <+> for ListT]]
--   ListT $ { [x1,..,xn] <- runListT aM ; { xs <- runListT (k1 x1) ; runListT $ msums $ map k2 xs } <+> .. <+> { xs <- runListT (k1 xn) ; runListT $ msums $ map k2 xs } }
--   = [[<+> distribute with >>=]]
--   ListT $ { [x1,..,xn] <- runListT aM ; xs <- (runListT (k1 x1) <+> .. <+> runListT (k1 xn)) ;  runListT $ msums $ map k2 xs }
--   = [[definition of msums and map]]
--   ListT $ { [x1,..,xn] <- runListT aM ; xs <- runListT $ msums $ map k1 [x1,..,xn] ; runListT $ msums $ map k2 xs }
--   = [[collapsing [x1,..,xn]]]
--   ListT $ { xs' <- runListT aM ; xs <- runListT $ msums $ map k1 xs' ; runListT $ msums $ map k xs }
--   =
--   RHS
--
--   LHS = RHS
--   QED }}}
--
-- }}}

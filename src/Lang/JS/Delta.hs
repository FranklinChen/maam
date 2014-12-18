module Lang.JS.Delta where

import Prelude (truncate, fromIntegral)
import FP hiding (inject)

import Data.Bits
import Data.Fixed
import Data.Word
import Text.Read

import Lang.JS.StateSpace
import Lang.JS.Syntax

class Prismable a b where
  pcoerce :: a -> Maybe b
  pinject :: b -> a

instance Prismable AValue Double where
  pinject = LitA . N
  pcoerce = coerce (nL <.> litAL)
instance Prismable AValue Bool where
  pinject = LitA . B
  pcoerce = coerce (bL <.> litAL)
instance Prismable AValue String where
  pinject = LitA . S
  pcoerce = coerce (sL <.> litAL)

class (Prismable a b) => BottomPrismable a b where
  pcoerceBot :: P b -> a -> Maybe ()
  pbot :: P b -> a

instance BottomPrismable AValue Double where
  pcoerceBot _ = coerce numAL
  pbot _ = NumA
instance BottomPrismable AValue Bool where
  pcoerceBot _ = coerce boolAL
  pbot _ = BoolA
instance BottomPrismable AValue String where
  pcoerceBot _ = coerce strAL
  pbot _ = StrA

liftBinaryOpBot :: (BottomPrismable AValue a) => (BottomPrismable AValue c) =>
                   P a -> P c -> (a -> a -> c) -> AValue -> AValue -> Set AValue
liftBinaryOpBot pa pc op av1 av2 =
  joins $ map liftMaybeSet $
  [ do
       v1 <- pcoerce av1
       v2 <- pcoerce av2
       return $ pinject $ op v1 v2
  , pcoerceBot pa av1 >> (return $ pbot pc)
  , pcoerceBot pa av2 >> (return $ pbot pc)
  ]

liftUnaryOpBot :: (BottomPrismable AValue a) => (BottomPrismable AValue b) =>
                P a -> P b -> (a -> b) -> AValue -> Set AValue
liftUnaryOpBot pa pb op av1 =
  joins $ map liftMaybeSet $
  [ do
       v1 <- pcoerce av1
       return $ pinject $ op v1
  , pcoerceBot pa av1 >> (return $ pbot pb)
  ]

binOp :: String -> (a -> a -> b) -> [a] -> String :+: b
binOp name op args = case args of
  [av1, av2] -> Inr $ op av1 av2
  _ -> Inl $ name ++ " only takes two arguments"

unaryOp :: String -> (a -> b) -> [a] -> String :+: b
unaryOp name op args = case args of
  [av1] -> Inr $ op av1
  _ -> Inl $ name ++ " only takes two arguments"

evalOp :: Op -> [AValue] -> String :+: Set AValue
evalOp o = case o of
  OStrPlus  -> binOp "Append"     $ liftBinaryOpBot P P ((++)   :: String -> String -> String)
  ONumPlus  -> binOp "Add"        $ liftBinaryOpBot P P ((+)    :: Double -> Double -> Double)
  OMul      -> binOp "Multiply"   $ liftBinaryOpBot P P ((*)    :: Double -> Double -> Double)
  ODiv      -> binOp "Divide"     $ liftBinaryOpBot P P ((-)    :: Double -> Double -> Double)
  OMod      -> binOp "Modulo"     $ liftBinaryOpBot P P ((mod') :: Double -> Double -> Double)
  OSub      -> binOp "Subtract"   $ liftBinaryOpBot P P ((-)    :: Double -> Double -> Double)
  OLt       -> binOp "LessThan"   $ liftBinaryOpBot P P ((<)    :: Double -> Double -> Bool  )
  OStrLt    -> binOp "StrLT"      $ liftBinaryOpBot P P ((<)    :: String -> String -> Bool  )
  OBAnd     -> binOp "BitwiseAnd" $ liftBinaryOpBot P P (bAnd   :: Double -> Double -> Double)
  OBOr      -> binOp "BitwiseOr"  $ liftBinaryOpBot P P (bOr    :: Double -> Double -> Double)
  OBXOr     -> binOp "BitwiseXOr" $ liftBinaryOpBot P P (bXOr   :: Double -> Double -> Double)
  OBNot   -> unaryOp "BitwiseNot" $ liftUnaryOpBot  P P (bNeg   :: Double -> Double)
  OLShift   -> binOp "LeftShift"          $ liftBinaryOpBot P P (shiftLeft          :: Double -> Double -> Double)
  OSpRShift -> binOp "SignedRightShift"   $ liftBinaryOpBot P P (signedShiftRight   :: Double -> Double -> Double)
  OZfRShift -> binOp "UnsignedRightShift" $ liftBinaryOpBot P P (unsignedShiftRight :: Double -> Double -> Double)
  OStrictEq   -> binOp "TripleEquals" $ tripleEquals
  OAbstractEq -> binOp "DoubleEquals" $ doubleEquals
  where
    bAnd = fromInteger .: ((.&.) `on` Prelude.truncate)
    bOr  = fromInteger .: ((.|.) `on` Prelude.truncate)
    bXOr = fromInteger .: (xor `on` Prelude.truncate)
    bNeg = fromInteger . complement . Prelude.truncate
    shiftLeft          = fromInt .: shiftL `on` Prelude.truncate
    signedShiftRight   = fromInt .: shiftR `on` Prelude.truncate
    unsignedShiftRight n i =
      -- Word64 is a hack to force zero-filled right bit shifting bitshifting >_>
      fromIntegral $ (shiftR :: Word64 -> Int -> Word64) (Prelude.truncate n) $ Prelude.truncate i
    tripleEquals a b = singleton $ case (a,b) of
      (LitA a', LitA b') -> LitA $ B $ a' == b'
      (LocA a', LocA b') -> LitA $ B $ a' == b'
      (_, _)             -> BoolA
    doubleEquals x y = singleton $ case (x,y) of
      (LitA a  , LitA b ) -> pinject $ litDoubleEquals a b
      (NumA    , NumA   ) -> BoolA
      (StrA    , StrA   ) -> BoolA
      (BoolA   , BoolA  ) -> BoolA
      (StrA    , BoolA  ) -> pinject False
      (BoolA   , StrA   ) -> pinject False
      (NumA    , StrA   ) -> BoolA
      (StrA    , NumA   ) -> BoolA
      -- I think heap objects are desugared away at this point?
      (CloA _c1 , CloA _c2) -> undefined -- TODO: Can this ever happen?
      (ObjA _o1 , ObjA _o2) -> undefined -- TODO: Can this ever happen? (I'm pretty sure this doesn't happen c.f. 11.9.3 step 13)
      (LocA _l1 , LocA _l2) -> pinject False     -- TODO: Can this ever happen? (I think it's false judging from ECMAEnvironment.hs:abstractEquality
      (_       , _      ) -> pinject False
    litDoubleEquals x y = case (x,y) of
      (UndefinedL , NullL     ) -> True
      (NullL      , UndefinedL) -> True
      (S s        , N n       ) -> litDoubleEquals (N $ stringToNumber s) (N n)
      (N n        , S s       ) -> litDoubleEquals (N $ stringToNumber s) (N n)
      (B b        , N n       ) -> litDoubleEquals (N $ booleanToNumber b) (N n)
      (N n        , B b       ) -> litDoubleEquals (N $ booleanToNumber b) (N n)
      (_          , _         ) -> x == y
    stringToNumber s = case (readMaybe (toChars s) :: Maybe Double) of
      Nothing -> haskellNaN
      Just n  -> n
    haskellInfinity = (1/0 :: Double)
    haskellNaN      = (0/0 :: Double)
    booleanToNumber b = if b then 1 else 0

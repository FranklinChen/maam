module Lang.JS.JS where

import Prelude (truncate)
import FP hiding (Kon, throw)
import Lang.JS.Syntax
import MAAM
import qualified FP.Pretty as P
import Lang.Common (VarLam(..))
import Data.Bits
import Data.Fixed

newtype Addr = Addr Int 
  deriving (Eq, Ord, Pretty)
newtype KAddr = KAddr Int
  deriving (Eq, Ord, Peano)

type Store = Map Addr (Set AValue)
type Env = Map Name Addr
type KStore = Map KAddr (Frame, KAddr)

-- o => {{ 4, { x: 1, y: 4 } }}
-- o.x
-- ----->  {{ 1 }}
--

-- all states == {{ o.x     [ o => {{ 4, { x: 1, y: 4 }] [ k => ∙ ] }}
--                , 1       [ o => ...                 ] [ k => ∙ ] }}
--                , Err NAO [ o => ...                 ] [ k => ∙ ] }}
--               }}
--

data Σ = Σ 
  { env :: Env
  , store :: Store
  , kstore :: KStore
  , kon :: KAddr
  , nextAddr :: Addr
  , nextKAddr :: KAddr
  } deriving (Eq, Ord)
instance Initial Σ where
  initial = Σ mapEmpty mapEmpty mapEmpty (KAddr 0) (Addr 0) (KAddr 0)

data Clo = Clo
  { arg :: [Name]
  , body :: Exp
  }
  deriving (Eq, Ord)

data Obj = Obj
  { fields :: [(String, (Set AValue))]
  }
  deriving (Eq, Ord)

data AValue =
    LitA Lit
  | NumA
  | StrA
  | BoolA
  | CloA Clo
  | ObjA Obj
    -- Fig 2. Mutable References
  | LocA Addr
  deriving (Eq, Ord)

data Frame = LetK [(Name, Set AValue)] Name [(Name, Exp)] Exp
           | AppL [Exp]
           | AppR (Set AValue) [(Set AValue)] [Exp]
           | ObjK [(String, (Set AValue))] Name [(Name, Exp)]
             -- Array Dereferencing
           | FieldRefL Exp
           | FieldRefR (Set AValue)
             -- Array Assignment
           | FieldSetA Exp         Exp
           | FieldSetN (Set AValue) Exp
           | FieldSetV (Set AValue) (Set AValue)
             -- Property Deletion
           | DeleteL Exp
           | DeleteR (Set AValue)
             -- Fig 2. Mutable References
           | RefSetL Exp
           | RefSetR (Set AValue)
           | RefK
           | DeRefK
             -- Fig 8. Control Operators
           | IfK Exp Exp
           | SeqK Exp
           | WhileL Exp Exp
           | WhileR Exp Exp
           | LabelK Label
           | BreakK Label
           | TryCatchK Exp Name
           | TryFinallyL Exp
           | TryFinallyR (Set AValue)
           | ThrowK
             -- Fig 9. Primitive Operations
           | PrimOpK Op [(Set AValue)] [Exp]
           deriving (Eq, Ord)

makeLenses ''Σ
makePrisms ''AValue

newtype Kon = Kon [Frame]

instance Pretty Frame where
  -- pretty (PrimK o k) = P.app [pretty o, P.lit "□", pretty k]
  pretty (LetK nvs n nes b) = P.app [P.con "let", pretty n, P.lit "= □", pretty b]
  pretty (AppL a) = P.app [P.lit "□", pretty a]
  pretty (AppR f vs es) = P.app [pretty f, pretty vs, P.lit "□", pretty es]
  pretty (ObjK _vs n _es) = P.app [ P.lit "{ ..."
                                  , pretty n
                                  , P.lit ":"
                                  , P.lit "□ ,"
                                  , P.lit "... }"
                                  ]
  -- Array Dereferencing
  pretty (FieldRefL i) = P.app [ P.lit "□"
                               , P.lit "["
                               , pretty i
                               , P.lit "]"
                               ]
  pretty (FieldRefR a) = P.app [ pretty a
                               , P.lit "["
                               , P.lit "□"
                               , P.lit "]"
                               ]
  -- Array Assignment
  pretty (FieldSetA   i e) = P.app [ P.lit "□"
                                   , P.lit "["
                                   , pretty i
                                   , P.lit "]"
                                   , P.lit "="
                                   , pretty e
                                   ]
  pretty (FieldSetN a   e) = P.app [ pretty a
                                   , P.lit "["
                                   , P.lit "□"
                                   , P.lit "]"
                                   , P.lit "="
                                   , pretty e
                                   ]
  pretty (FieldSetV a v  ) = P.app [ pretty a
                                   , P.lit "["
                                   , pretty v
                                   , P.lit "]"
                                   , P.lit "="
                                   , P.lit "□"
                                   ]
  -- Property Deletion
  pretty (DeleteL e) = P.app [ P.lit "delete"
                             , P.lit "□"
                             , P.lit "["
                             , pretty e
                             , P.lit "]"
                             ]
  pretty (DeleteR a) = P.app [ P.lit "delete"
                             , pretty a
                             , P.lit "["
                             , P.lit "□"
                             , P.lit "]"
                             ]
  -- Fig 2. Mutable References
  pretty (RefSetL e) = P.app [ P.lit "□"
                             , P.lit " := "
                             , pretty e
                             ]
  pretty (RefSetR v)  = P.app [ pretty v
                              , P.lit " := "
                              , P.lit "□"
                              ]
  pretty RefK = P.lit "RefK"
  pretty DeRefK = P.lit "DeRefK"
  -- Fig 8. Control Operators
  pretty (IfK tb fb) = P.app [ P.lit "□"
                             , pretty tb
                             , pretty fb
                             ]
  pretty (SeqK e) = P.app [ P.lit "□ ;"
                          , pretty e
                          ]
  pretty (WhileL _c b) = P.app [ P.lit "while □ {"
                               , pretty b
                               , P.lit "}"
                               ]
  pretty (WhileR c _b) = P.app [ P.lit "while "
                               , pretty c
                               , P.lit "{"
                               , P.lit "□"
                               , P.lit "}"
                               ]
  pretty (LabelK l) = P.app [ P.lit "label"
                            , pretty l
                            , P.lit ": □"
                            ]
  pretty (BreakK l) = P.app [ P.lit "break"
                            , pretty l
                            , P.lit ":"
                            , P.lit ": □"
                            ]
  pretty (TryCatchK e n) = P.app [ P.lit "try"
                                 , P.lit "{"
                                 , P.lit "□"
                                 , P.lit "}"
                                 , P.lit "catch"
                                 , P.lit "("
                                 , pretty n
                                 , P.lit ")"
                                 , P.lit "}"
                                 , pretty e
                                 , P.lit "}"
                                 ]
  pretty (TryFinallyL e) = P.app [ P.lit "try"
                                 , P.lit "{"
                                 , P.lit "□"
                                 , P.lit "}"
                                 , P.lit "finally"
                                 , P.lit "{"
                                 , pretty e
                                 , P.lit "}"
                                 ]
  pretty (TryFinallyR v) = P.app [ P.lit "try"
                                 , P.lit "{"
                                 , pretty v
                                 , P.lit "}"
                                 , P.lit "finally"
                                 , P.lit "{"
                                 , P.lit "□"
                                 , P.lit "}"
                                 ]
  pretty ThrowK = P.app [ P.lit "throw" ]
  -- Fig 9. Primitive Operations
  pretty (PrimOpK o vs es) = P.app [ pretty o
                                   , pretty vs
                                   , P.lit "□"
                                   , pretty es
                                   ]

class
  ( Monad m
  , MonadStateE Σ m
  , MonadZero m
  , MonadPlus m
  , MonadStep ς m
  , JoinLattice (ς Exp)
  , Inject ς
  , PartialOrder (ς Exp)
  ) => Analysis ς m | m -> ς where

instance (Eq a) => (Indexed a v [(a, v)]) where
  -- O(n)
  ((s,v):alist) # s'
    | s == s'   = Just v
    | otherwise = alist # s
  [] # _        = Nothing

instance (Eq a) => (MapLike a v [(a, v)]) where
  -- fuck it

instance Pretty Clo where
  pretty (Clo x b) = pretty $ VarLam [x] b
instance Pretty Obj where
  pretty (Obj fds) =
    P.nest 2 $ P.hvsep
    [ P.lit "{"
    , exec [P.hsep $
            map (\(n,e) ->
                  exec [ pretty n
                       , P.lit ":"
                       , pretty e
                       ])
                fds]
    , P.lit "}"
    ]

instance Pretty AValue where
  pretty (LitA l) = pretty l
  pretty NumA = P.con "ℝ"
  pretty StrA = P.con "S"
  pretty (CloA c) = pretty c
  pretty (ObjA o) = pretty o
  pretty (LocA l) = pretty l

check :: a -> Bool -> a :+: ()
check _err True  = Inr ()
check err  False = Inl err

liftToEither :: l -> Maybe r -> l :+: r
liftToEither l Nothing  = Inl l
liftToEither _ (Just r) = Inr r

notANum :: AValue -> Maybe r -> String :+: r
notANum v =
  liftToEither $ -- (show (pretty v)) ++
  "something cannot be coerced to a number"

mustCoerceToNum :: AValue -> String :+: Double
mustCoerceToNum v = undefined -- notANum v $ coerce (nL <.> numAL) v

binaryOp :: String
            -> (a -> a -> Set AValue)
            -> AValue
            -> (AValue -> String :+: a)
            -> [AValue]
            -> String :+: (Set AValue)
binaryOp name op bot coerce args =
  case args of
    [v1,v2] ->
      if v1 == bot || v2 == bot
        then Inr $ singleton $ bot
        else do
        n1 <- coerce v1
        n2 <- coerce v2
        Inr $ op n1 n2
    _ -> Inl $ name ++ " must be applied to two arguments"

wrapIt :: (a -> b -> c) -> (c -> d) -> a -> b -> d
wrapIt f g a b = g $ f a b

binaryNumericOp :: String -> (Double -> Double -> Double) -> [AValue] -> String :+: Set AValue
binaryNumericOp name op args =
  binaryOp name (wrapIt op $ singleton . LitA . N) NumA mustCoerceToNum args

binaryNumericComparisonOp :: String -> (Double -> Double -> Bool) -> [AValue] -> String :+: Set AValue
binaryNumericComparisonOp name op args =
  binaryOp name (wrapIt op $ singleton . LitA . B) BoolA mustCoerceToNum args

unaryNumericOp :: String -> (Double -> Double) -> [AValue] -> String :+: Set AValue
unaryNumericOp name op args =
  case args of
    [NumA] ->
      Inr $ singleton NumA
    [v] -> do
      n <- mustCoerceToNum v
      Inr $ singleton $ LitA $ N $ op n
    _ -> Inl $ name ++ " must be applied to two arguments"

evalOp :: Op -> [AValue] -> String :+: Set AValue
evalOp o args = case o of
  OStrPlus  -> undefined -- TODO: string prim ops
  ONumPlus  -> binaryNumericOp "Plus"     (+) args
  OMul      -> binaryNumericOp "Multiply" (-) args
  ODiv      -> binaryNumericOp "Divide"   (-) args
  OMod      -> binaryNumericOp "Modulo"   (mod') args
  OSub      -> binaryNumericOp "Subtract" (-) args
  OLt       -> binaryNumericComparisonOp "LessThan" (<) args
  OStrLt    -> undefined -- TODO: string prim ops
  OBAnd     -> binaryNumericOp "BitwiseAnd" (fromInteger .: ((.&.) `on` Prelude.truncate)) args
  OBOr      -> binaryNumericOp "BitwiseOr"  (fromInteger .: ((.|.) `on` Prelude.truncate)) args
  OBXOr     -> binaryNumericOp "BitwiseXOr" (fromInteger .: (xor `on` Prelude.truncate)) args
  OBNot     -> unaryNumericOp  "BitwiseNot" (fromInteger . complement . Prelude.truncate) args

-- litAL :: Prism AValue Lit
-- numAL :: Prism AValue ()
-- cloAL :: Prism AValue Clo
-- coerce cloAL :: AValue -> Maybe Clo
-- etc. ...

pushFrame :: (Analysis ς m) => Frame -> m ()
pushFrame fr = do
  fp  <- getL konL
  fp' <- nextFramePtr
  modifyL kstoreL $ mapInsert fp' (fr, fp)
  putL konL fp

popFrame :: (Analysis ς m) => m Frame
popFrame = do
  fp <- getL konL
  kσ <- getL kstoreL
  (fr, fp') <- liftMaybeZero $ kσ # fp
  putL konL fp'
  return fr

eval :: (Analysis ς m) => Exp -> m Exp
eval e =
  case stampedFix e of
    Lit l -> kreturn $ singleton $ LitA l
    Var x -> var x
    Func xs b -> kreturn $ singleton $ CloA $ Clo xs b
    ObjE [] -> do
      kreturn $ singleton $ ObjA $ Obj []
    ObjE ((n',e'):nes) -> do
      pushFrame (ObjK [] n' nes)
      return e'
    Let [] b -> do
      return b
    Let ((n,e):nes) b -> do
      pushFrame $ LetK [] n nes b
      return e
    App f args -> do
      pushFrame (AppL args)
      return f
    FieldRef o i -> do
      pushFrame (FieldRefL i)
      return o
    FieldSet o i v -> do
      pushFrame (FieldSetA i v)
      return o
    Delete o i -> do
      pushFrame (DeleteL i)
      return o
    -- Fig 2. Mutable References
    RefSet l v -> do
      pushFrame (RefSetL v)
      return l
    Ref v -> do
      pushFrame RefK
      return v
    DeRef l -> do
      pushFrame DeRefK
      return l
    -- Fig 8. Control Operators
    If c tb fb -> do
      pushFrame $ IfK tb fb
      return c
    Seq e₁ e₂ -> do
      pushFrame $ SeqK e₂
      return e₁
    While c b -> do
      pushFrame $ WhileL c b
      return c
    LabelE ln e -> do
      pushFrame $ LabelK ln
      return e
    Break ln e -> do
      pushFrame $ BreakK ln
      return e
    TryCatch e₁ n e₂ -> do
      pushFrame $ TryCatchK e₂ n
      return e₁
    TryFinally e₁ e₂ -> do
      pushFrame $ TryFinallyL e₂
      return e₁
    Throw e -> do
      pushFrame $ ThrowK
      return e
    -- Fig 9. Primitive Operations
    PrimOp o [] -> do
      returnEvalOp o []
    PrimOp o (arg:args) -> do
      pushFrame $ PrimOpK o [] args
      return arg


bind :: (Analysis ς m) => Name -> Set AValue -> m ()
bind x v = do
  l <- nextLocation
  modifyL envL $ mapInsert x l -- TODO: Is this right?
  modifyL storeL $ mapInsertWith (\/) l v

bindMany :: (Analysis ς m) => [Name] -> [Set AValue] -> m ()
bindMany []     []     = return ()
bindMany (x:xs) (v:vs) = bind x v >> bindMany xs vs
bindMany []     _      = mzero
bindMany _      []     = mzero

kreturn :: (Analysis ς m) => Set AValue -> m Exp
kreturn v = do
  fr <- popFrame
  s <- kreturn' v fr
  return s

snameToString :: Name -> String
snameToString = getName

kreturn' :: forall ς m. (Analysis ς m) => Set AValue -> Frame -> m Exp
kreturn' v fr = case fr of
  LetK nvs n ((n',e'):nes) b -> do
    bind n v
    touchNGo e' $ LetK nvs n' nes b
  LetK nvs n [] b -> do
    bind n v
    return b
  AppL [] ->
    kreturn' v $ AppR v [] []
  AppL (arg:args) ->
    touchNGo arg $ AppR v [] args
  AppR v vs (arg:args) -> do
    touchNGo arg $ AppR v vs args
  AppR fv argvs [] -> do
    Clo xs b <- liftMaybeZero . coerce cloAL *$ mset fv
    bindMany xs argvs
    return b
  ObjK nvs n ((n',e'):nes) -> do
    let nvs' = (snameToString n, v) : nvs
    touchNGo e' $ ObjK nvs' n' nes
  ObjK nvs n [] -> do
    let nvs' = (snameToString n, v) : nvs
        o    = ObjA $ Obj nvs'
    tailReturn $ singleton o
  FieldRefL i -> do
    touchNGo i $ FieldRefR v
  FieldRefR o -> do
    σ <- getL storeL
    -- v :: Set AValue
    -- coerceStrTop *$ v :: Set (String :+: ())
    -- WANT :: (Set String) :+: ()
    -- o = { x: 1, y: 2 }
    -- a = o["z"]
    -- a === undefined <-- return TRUE
    -- a.foo           <-- BAD
    --                     Q: Does this 1) throw an error or 2) it's a stuck state.
    -- NEED:
    -- type AbsValue = Set AValue
    -- type AbsString = Maybe (Set String)
    -- you will need a [toIndex :: AbsValue -> AbsString]
    --
    -- Probably:
    -- We have a lot more stuck states right now that are incorrect, and really should be thrown errors.
    let v' = msum
          [ do
              let fieldnames :: Set String
                  fieldnames = liftMaybeSet . coerce (sL <.> litAL) *$ v
              prototypalLookup σ o *$ fieldnames
          , do
              liftMaybeSet . coerce strAL *$ v
              -- get all possible field values
              undefined

          ]
    tailReturn v'
    -- let fieldnames = coerceStrSet *$ v
    --     v' = prototypalLookup σ o *$ fieldnames
    -- tailReturn v'
  FieldSetA i e -> do
    touchNGo i $ FieldSetN v e
  FieldSetN o e -> do
    touchNGo e $ FieldSetV o v
  FieldSetV o i -> do
    let o' = do
          Obj fields <- coerceObjSet *$ o
          fieldname <- coerceStrSet *$ i
          singleton $ ObjA $ Obj $
            mapModify (\_ -> v) fieldname fields
    tailReturn o'
  DeleteL e -> do
    touchNGo e $ DeleteR v
  DeleteR o -> do
    let o' = do
          Obj fields <- coerceObjSet *$ o
          fieldname <- coerceStrSet *$ v
          singleton $ ObjA $ Obj $
            filter (\(k,_) -> k /= fieldname) fields
    tailReturn o'
  -- Fig 2. Mutable References
  RefSetL e -> do
    touchNGo e $ RefSetR v
  RefSetR l -> do
    σ <- getL storeL
    -- TODO: This cannot possibly be the right way to do this ...
    let locs = l >>= coerceLocSet
        σ'   = foldr (\l -> (\σ -> mapInsertWith (\/) l v σ)) σ locs
    putL storeL σ'
    tailReturn v
  RefK -> do
    l <- nextLocation
    modifyL storeL $ mapInsertWith (\/) l v
    tailReturn $ singleton $ LocA l
  DeRefK -> do
    σ <- getL storeL
    let locs = v >>= coerceLocSet
        v'   = mjoin . liftMaybeSet . index σ *$ locs
    tailReturn v'
  -- Fig 8. Control Operators
  IfK tb fb -> do
    b <- mset $ coerceBool *$ v
    if b
      then return tb
      else return fb
  SeqK e₂ -> do
    return e₂
  WhileL c e -> do
    b <- mset $ coerceBool *$ v
    if b
      then pushFrame (WhileR c e) >> return e
      else tailReturn $ singleton $ LitA UndefinedL
  WhileR c b -> do
    touchNGo c $ WhileL c b
  LabelK _l -> do
    tailReturn v
  BreakK l -> do
    popToLabel l v
  TryCatchK _e₂ _n -> do
    tailReturn v
  TryFinallyL e₂ -> do
    touchNGo e₂ $ TryFinallyR v
  TryFinallyR result -> do
    tailReturn result
  ThrowK -> do
    throw v
  -- Fig 9. Primitive Operators
  PrimOpK o vs (e:es) -> do
    touchNGo e $ PrimOpK o (v:vs) es
  PrimOpK o vs [] -> do
    returnEvalOp o $ reverse $ v:vs

touchNGo :: (Analysis ς m) => Exp -> Frame -> m Exp
touchNGo e fr = do
  pushFrame fr
  return e

tailReturn :: (Analysis ς m) => Set AValue -> m Exp
tailReturn v = popFrame >>= (kreturn' v)

popToLabel :: (Analysis ς m) => Label -> Set AValue -> m Exp
popToLabel l v = do
  fr <- popFrame
  case fr of
    LabelK l' ->
      if l == l'
      then tailReturn v
      else popToLabel l v
    TryFinallyL e -> do
      pushFrame $ BreakK l
      return e
    _ -> popToLabel l v

throw :: (Analysis ς m) => Set AValue -> m Exp
throw v = do
  fr <- popFrame
  case fr of
    TryCatchK e n -> do
      bind n v
      return e
    TryFinallyL e -> do
      pushFrame $ ThrowK
      return e
    _ ->
      throw v

crossproduct :: [Set AValue] -> Set [AValue]
crossproduct = toSet . sequence . map toList 

failIfAnyFail :: (Ord b) => Set (a :+: b) -> a :+: Set b
failIfAnyFail = map toSet . sequence . toList

returnEvalOp :: (Analysis ς m) => Op -> [Set AValue] -> m Exp
returnEvalOp o args =
  let vs  = setMap (evalOp o) (crossproduct args)
      vs' = failIfAnyFail vs
  in case vs' of
    Inl msg -> throw $ singleton $ LitA $ S msg
    Inr vs'' -> tailReturn $ mjoin vs''

-- 1. have this take [AValue] instead of [Set AValue]
-- 2. directly encode the logic of "if we know the string, do the lookup, if not, return all fields"
prototypalLookup :: Store -> Set AValue -> String -> Set AValue
prototypalLookup σ o fieldname = do
  Obj fields <- coerceObjSet *$ o
  case fields # fieldname of
    Just v -> v
    Nothing ->
      case fields # "__proto__" of
        Nothing ->
          singleton $ LitA UndefinedL
        Just avs ->
          avs >>= lookupInParent
  where
    lookupInParent av =
      case av of
        LitA NullL ->
          singleton $ LitA UndefinedL
        (LocA l) ->
          case σ # l of
            Nothing -> singleton $ LitA UndefinedL
            Just vs -> prototypalLookup σ vs fieldname
        _ ->
          -- __proto__ has been set to something other than an object
          -- I *think* this case is exactly the same as LitA NullL, but
          -- λJS doesn't actually specify what to do in this case
          singleton $ LitA UndefinedL

var :: (Analysis ς m) => Name -> m Exp
var x = do
  σ <- getL storeL
  e <- getL envL
  kreturn $ mjoin . liftMaybeSet . index σ *$ liftMaybeSet $ e # x

coerceBool :: AValue -> Set Bool
coerceBool v = msum
  [ do
      liftMaybeSet $ coerce boolAL v
      singleton True <+> singleton False
  , liftMaybeSet $ coerce (bL <.> litAL) v
  ]

coerceStrSet :: AValue -> Set String
coerceStrSet = undefined

coerceStrTop :: AValue -> Maybe (String :+: ())
coerceStrTop v = undefined
  -- msum
  -- [ do
  --     coerce strAL v
  --     return $ Inr ()
  -- -- , coerce (sL <.> litAL) v
  -- ]

isStrEq :: AValue -> String -> Set Bool
isStrEq = undefined

coerceObj :: (Analysis ς m) => AValue -> m Obj
coerceObj = undefined

coerceObjSet :: AValue -> Set Obj
coerceObjSet = undefined

coerceLoc :: (Analysis ς m) => AValue -> m Addr
coerceLoc = undefined

coerceLocSet :: AValue -> Set Addr
coerceLocSet = undefined

nextLocation :: (Analysis ς m) => m Addr
nextLocation = do
  Addr l <- getL nextAddrL
  putL nextAddrL $ Addr $ l + 1
  return $ Addr l

nextFramePtr :: (Analysis ς m) => m KAddr
nextFramePtr = do
  KAddr ptr <- getL nextKAddrL
  putL nextKAddrL $ KAddr $ ptr + 1
  return $ KAddr ptr


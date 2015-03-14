module MAAM.Inject where

import FP

class Inject ς where inj :: a -> ς a

instance                         Inject ID             where inj = ID
instance                         Inject ListSet        where inj = single
instance                         Inject ListSetWithTop where inj = single
instance (Bot 𝓈)              => Inject ((,) 𝓈)        where inj = (bot,)
instance (Inject t, Inject u) => Inject (t :.: u)      where inj = Compose . inj . inj

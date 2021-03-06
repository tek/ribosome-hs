module Ribosome.Menu.Data.MenuConsumerUpdate where

import Ribosome.Menu.Data.MenuUpdate (MenuUpdate)

data MenuConsumerUpdate m a i =
  MenuConsumerUpdate {
    _changed :: Bool,
    _menu :: MenuUpdate m a i
  }

module Ribosome.Data.Scratch where

import Ribosome.Nvim.Api.Data (Buffer, Tabpage, Window)

data Scratch =
  Scratch {
    scratchName :: String,
    scratchBuffer :: Buffer,
    scratchWindow :: Window,
    scratchTab :: Maybe Tabpage
  }
  deriving (Eq, Show)

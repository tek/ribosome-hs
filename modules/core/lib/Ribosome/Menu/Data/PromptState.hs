{-# LANGUAGE TemplateHaskell #-}

module Ribosome.Menu.Data.PromptState where

data PromptState =
  Insert
  |
  Normal
  deriving (Eq, Show)

deepLenses ''PromptState

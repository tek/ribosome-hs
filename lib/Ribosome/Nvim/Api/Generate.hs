{-# LANGUAGE TemplateHaskell #-}

module Ribosome.Nvim.Api.Generate where

import Control.Monad (join)
import Data.Bifunctor (first)
import Data.Char (toUpper)
import Data.Int (Int64)
import Data.Map (Map)
import qualified Data.Map as Map (lookup)
import Data.Maybe (fromMaybe)
import Language.Haskell.TH
import Neovim.API.Parser (
  NeovimAPI(functions),
  NeovimFunction(NeovimFunction),
  NeovimType(NestedType, SimpleType, Void),
  customTypes,
  parseAPI,
  )
import Neovim.API.TH (defaultAPITypeToHaskellTypeMap)

camelcase :: String -> String
camelcase =
  snd . foldr folder (False, "")
  where
    folder '_' (_, z) = (True, z)
    folder a (True, h : t) = (False, a : toUpper h : t)
    folder a (True, []) = (False, [a])
    folder a (False, z) = (False, a : z)

apiTypeToHaskellType :: Map String (Q Type) -> NeovimType -> Q Type
apiTypeToHaskellType typeMap at =
  case at of
    Void -> [t|()|]
    NestedType t Nothing ->
      appT listT $ apiTypeToHaskellType typeMap t
    NestedType t (Just n) ->
      foldl appT (tupleT n) . replicate n $ apiTypeToHaskellType typeMap t
    SimpleType t ->
      fromMaybe (conT . mkName $ t) $ Map.lookup t typeMap

data FunctionData =
  FunctionData {
    apiName :: String,
    ccName :: Name,
    async :: Bool,
    names :: [Name],
    types :: [Type]
    }
  deriving (Eq, Show)

functionData :: Map String (Q Type) -> NeovimFunction -> Q FunctionData
functionData nvimTypes (NeovimFunction name parameters _ async _) = do
  names <- traverse newName prefixedNames
  types <- traverse (apiTypeToHaskellType nvimTypes) (fst <$> parameters)
  return (FunctionData name (mkName . camelcase $ name) async names types)
  where
    prefix i n = "arg" ++ show i ++ "_" ++ n
    prefixedNames = zipWith prefix [0 :: Int ..] (snd <$> parameters)

generateFromApi :: (FunctionData -> Q [Dec]) -> (Name -> Int64 -> DecsQ) -> Q [Dec]
generateFromApi handleFunction handleExtType = do
  api <- either (fail . show) return =<< runIO parseAPI
  funcs <- traverse (functionData defaultAPITypeToHaskellTypeMap) (functions api)
  funcDecs <- traverse handleFunction funcs
  tpeDecs <- traverse (uncurry handleExtType) $ first mkName <$> customTypes api
  return $ join (funcDecs ++ tpeDecs)

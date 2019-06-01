module Ribosome.Test.Unit where

import Control.Monad.IO.Class (MonadIO)
import Data.Default (def)
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.Log.Logger (Priority(DEBUG), setLevel, updateGlobalLogger)

import Ribosome.Control.Monad.Ribo (MonadRibo, NvimE, pluginName)
import Ribosome.Control.Ribosome (Ribosome)
import Ribosome.Error.Report.Class (ReportError)
import Ribosome.Plugin.RpcHandler (RpcHandler)
import Ribosome.Test.Embed (Runner, TestConfig(..), setupPluginEnv, unsafeEmbeddedSpecR)
import qualified Ribosome.Test.File as F (fixture, fixtureContent, tempDir)
import Ribosome.Test.Orphans ()

uPrefix :: Text
uPrefix = "u"

uSpec :: (MonadIO m, NvimE e m) => Runner m
uSpec conf spec = do
  setupPluginEnv conf
  spec

unitSpec ::
  (RpcHandler e (Ribosome env) m, ReportError e, MonadIO m, NvimE e' m) =>
  TestConfig ->
  env ->
  m () ->
  IO ()
unitSpec =
  unsafeEmbeddedSpecR uSpec

unitSpecDef ::
  (RpcHandler e (Ribosome env) m, ReportError e, MonadIO m, NvimE e' m) =>
  env ->
  m () ->
  IO ()
unitSpecDef =
  unitSpec def

unitSpecDef' ::
  (RpcHandler e (Ribosome ()) m, ReportError e, MonadIO m, NvimE e' m) =>
  m () ->
  IO ()
unitSpecDef' =
  unitSpecDef ()

tempDir :: MonadIO m => FilePath -> m FilePath
tempDir = F.tempDir uPrefix

tempFile :: MonadIO m => FilePath -> m FilePath
tempFile file = do
  absDir <- tempDir $ takeDirectory file
  return $ absDir </> takeFileName file

fixture :: MonadIO m => FilePath -> m FilePath
fixture = F.fixture uPrefix

fixtureContent :: MonadIO m => FilePath -> m Text
fixtureContent = F.fixtureContent uPrefix

withLogAs ::
  MonadIO m =>
  Text ->
  m a ->
  m a
withLogAs name thunk = do
  liftIO $ updateGlobalLogger (toString name) (setLevel DEBUG)
  thunk

withLog ::
  MonadRibo m =>
  m a ->
  m a
withLog thunk =
  (`withLogAs` thunk) =<< pluginName

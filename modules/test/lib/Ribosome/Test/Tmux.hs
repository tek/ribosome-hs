module Ribosome.Test.Tmux where

import Chiasma.Command.Pane (sendKeys)
import Chiasma.Data.TmuxError (TmuxError)
import Chiasma.Data.TmuxId (PaneId(PaneId))
import Chiasma.Monad.Stream (runTmux)
import Chiasma.Native.Api (TmuxNative(TmuxNative))
import qualified Chiasma.Test.Tmux as Chiasma (tmuxGuiSpec, tmuxSpec)
import Control.Monad.DeepError (MonadDeepError)
import Control.Monad.IO.Class (MonadIO)
import Control.Monad.Trans.Except (runExceptT)
import Data.DeepPrisms (DeepPrisms)
import Data.Default (Default(def))
import Data.Foldable (traverse_)
import Data.Functor (void)
import qualified Neovim.Context.Internal as Internal (
  Config,
  globalFunctionMap,
  mkFunctionMap,
  newConfig,
  pluginSettings,
  retypeConfig,
  )
import Neovim.RPC.Common (RPCConfig, SocketType(UnixSocket), createHandle, newRPCConfig)
import Neovim.RPC.EventHandler (runEventHandler)
import Neovim.RPC.SocketReader (runSocketReader)
import System.FilePath ((</>))
import UnliftIO (throwString)
import UnliftIO.Async (async, cancel)
import UnliftIO.Directory (doesPathExist)
import UnliftIO.Exception (bracket)
import UnliftIO.STM (atomically, putTMVar)
import UnliftIO.Temporary (withTempDirectory)

import Ribosome.Config.Setting (updateSetting)
import Ribosome.Config.Settings (tmuxSocket)
import Ribosome.Control.Concurrent.Wait (waitIODef)
import Ribosome.Control.Monad.Ribo (RiboN)
import Ribosome.Control.Ribosome (Ribosome(Ribosome), newRibosomeTVar)
import Ribosome.Error.Report.Class (ReportError)
import Ribosome.Nvim.Api.RpcCall (RpcError)
import Ribosome.Plugin (RpcHandler)
import Ribosome.Test.Embed (Runner, TestConfig(..), Vars, defaultTestConfigWith, runTest)
import Ribosome.Test.Orphans ()
import Ribosome.Test.Unit (fixture, tempDir, uSpec, unitSpec)

startHandlers :: FilePath -> TestConfig -> Internal.Config RPCConfig -> IO (IO ())
startHandlers socket TestConfig{..} nvimConf = do
  handle <- createHandle (UnixSocket socket)
  socketReader <- run runSocketReader handle
  eventHandler <- run runEventHandler handle
  atomically $ putTMVar (Internal.globalFunctionMap nvimConf) (Internal.mkFunctionMap [])
  let stopEventHandlers = traverse_ cancel [socketReader, eventHandler]
  return stopEventHandlers
  where
    run runner hand = async . void $ runner hand emptyConf
    emptyConf = nvimConf { Internal.pluginSettings = Nothing }

runTmuxNvim ::
  (RpcHandler e env m, ReportError e) =>
  TestConfig ->
  env ->
  m () ->
  FilePath ->
  IO ()
runTmuxNvim conf ribo specThunk socket = do
  nvimConf <- Internal.newConfig (pure Nothing) newRPCConfig
  let testCfg = Internal.retypeConfig ribo nvimConf
  bracket (startHandlers socket conf nvimConf) id (runTest conf testCfg specThunk)

externalNvimCmdline :: FilePath -> String
externalNvimCmdline socket =
  "nvim --listen " ++ socket ++ " -n -u NONE -i NONE"

runGui ::
  (RpcHandler e env m, ReportError e) =>
  TmuxNative ->
  FilePath ->
  TestConfig ->
  env ->
  m () ->
  IO ()
runGui api temp conf ribo specThunk = do
  void $ runExceptT @TmuxError $ runTmux api $ sendKeys (PaneId 0) [externalNvimCmdline socket]
  _ <- waitIODef (pure socket) doesPathExist
  runTmuxNvim conf ribo specThunk socket
  where
    socket = temp </> "nvim-socket"

unsafeGuiSpec ::
  (RpcHandler e env m, ReportError e) =>
  TmuxNative ->
  FilePath ->
  Runner m ->
  TestConfig ->
  env ->
  m () ->
  IO ()
unsafeGuiSpec api temp runner conf s specThunk =
  runGui api temp conf s $ runner conf specThunk

unsafeGuiSpecR ::
  (RpcHandler e (Ribosome env) m, ReportError e) =>
  TmuxNative ->
  FilePath ->
  Runner m ->
  TestConfig ->
  env ->
  m () ->
  IO ()
unsafeGuiSpecR api temp runner conf s specThunk = do
  tv <- newRibosomeTVar s
  let ribo = Ribosome (tcPluginName conf) tv
  unsafeGuiSpec api temp runner conf ribo specThunk

guiSpec ::
  DeepPrisms e RpcError =>
  ReportError e =>
  TestConfig ->
  TmuxNative ->
  s ->
  RiboN s e () ->
  IO ()
guiSpec conf api env specThunk = do
  socketDir <- tempDir "tmux-socket"
  withTempDirectory socketDir "spec" run
  where
    run tempdir =
      unsafeGuiSpecR api tempdir uSpec conf env specThunk

withTmux ::
  DeepPrisms e RpcError =>
  RiboN s e () ->
  TmuxNative ->
  RiboN s e ()
withTmux thunk (TmuxNative (Just socket)) =
  updateSetting tmuxSocket socket *> thunk
withTmux _ _ =
  throwString "no socket in test tmux"

tmuxGuiSpec ::
  DeepPrisms e RpcError =>
  ReportError e =>
  Default s =>
  TestConfig ->
  RiboN s e () ->
  IO ()
tmuxGuiSpec conf specThunk =
  Chiasma.tmuxGuiSpec run
  where
    run api = guiSpec conf api def (withTmux specThunk api)
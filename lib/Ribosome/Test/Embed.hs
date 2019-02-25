module Ribosome.Test.Embed(
  defaultTestConfig,
  defaultTestConfigWith,
  TestConfig (..),
  Vars(..),
  unsafeEmbeddedSpec,
  setVars,
  setupPluginEnv,
  quitNvim,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (runReaderT)
import Control.Monad.Trans.Resource (runResourceT)
import Data.Default (Default(def))
import Data.Foldable (traverse_)
import Data.Functor (void)
import Data.Maybe (fromMaybe)
import GHC.IO.Handle (Handle)
import Neovim (Neovim, Object, vim_set_var', vim_command)
import qualified Neovim.Context.Internal as Internal(
  Neovim(Neovim),
  Config,
  newConfig,
  retypeConfig,
  mkFunctionMap,
  pluginSettings,
  globalFunctionMap,
  )
import Neovim.RPC.Common (RPCConfig, newRPCConfig)
import Neovim.RPC.EventHandler (runEventHandler)
import Neovim.RPC.SocketReader (runSocketReader)
import System.Directory (makeAbsolute)
import System.Exit (ExitCode)
import qualified System.Posix.Signals as Signal (signalProcess, killProcess)
import System.Process (getPid)
import System.Process.Typed (
  ProcessConfig,
  Process,
  withProcess,
  proc,
  setStdin,
  setStdout,
  getStdin,
  getStdout,
  unsafeProcessHandle,
  createPipe,
  getExitCode,
  )
import UnliftIO.Async (async, cancel, race)
import UnliftIO.Exception (tryAny, bracket)
import UnliftIO.STM (atomically, putTMVar)

import Ribosome.Api.Option (rtpCat)
import Ribosome.Control.Ribo (Ribo)
import Ribosome.Control.Ribosome (Ribosome(Ribosome), newInternalTVar)
import Ribosome.Data.Time (sleep, sleepW)

type Runner env = TestConfig -> Neovim env () -> Neovim env ()

newtype Vars = Vars [(String, Object)]

data TestConfig =
  TestConfig {
    tcPluginName :: String,
    tcExtraRtp :: String,
    tcLogPath :: FilePath,
    tcTimeout :: Word,
    tcCmdline :: Maybe [String],
    tcCmdArgs :: [String],
    tcVariables :: Vars
  }

instance Default TestConfig where
  def = TestConfig "ribosome" "test/f/fixtures/rtp" "test/f/temp/log" 5 def def (Vars [])

defaultTestConfigWith :: String -> Vars -> TestConfig
defaultTestConfigWith name = TestConfig name "test/f/fixtures/rtp" "test/f/temp/log" 5 def def

defaultTestConfig :: String -> TestConfig
defaultTestConfig name = defaultTestConfigWith name (Vars [])

setVars :: Vars -> Neovim e ()
setVars (Vars vars) =
  traverse_ (uncurry vim_set_var') vars

setupPluginEnv :: TestConfig -> Neovim e ()
setupPluginEnv (TestConfig _ rtp _ _ _ _ vars) = do
  absRtp <- liftIO $ makeAbsolute rtp
  rtpCat absRtp
  setVars vars

killPid :: Integral a => a -> IO ()
killPid =
  void . tryAny . Signal.signalProcess Signal.killProcess . fromIntegral

killProcess :: Process i o e -> IO ()
killProcess prc = do
  let handle = unsafeProcessHandle prc
  mayPid <- getPid handle
  traverse_ killPid mayPid

testNvimProcessConfig :: TestConfig -> ProcessConfig Handle Handle ()
testNvimProcessConfig TestConfig {..} =
  setStdin createPipe $ setStdout createPipe $ proc "nvim" $ args ++ tcCmdArgs
  where
    args = fromMaybe defaultArgs tcCmdline
    defaultArgs = ["--embed", "-n", "-u", "NONE", "-i", "NONE"]

startHandlers :: NvimProc -> TestConfig -> Internal.Config RPCConfig -> IO (IO ())
startHandlers prc TestConfig{..} nvimConf = do
  socketReader <- run runSocketReader getStdout
  eventHandler <- run runEventHandler getStdin
  atomically $ putTMVar (Internal.globalFunctionMap nvimConf) (Internal.mkFunctionMap [])
  let stopEventHandlers = traverse_ cancel [socketReader, eventHandler]
  return stopEventHandlers
  where
    run runner stream = async . void $ runner (stream prc) emptyConf
    emptyConf = nvimConf { Internal.pluginSettings = Nothing }

runNeovimThunk :: Internal.Config e -> Neovim e a -> IO ()
runNeovimThunk cfg (Internal.Neovim thunk) =
  void $ runReaderT (runResourceT thunk) cfg

type NvimProc = Process Handle Handle ()

waitQuit :: NvimProc -> IO (Maybe ExitCode)
waitQuit prc =
  wait 30
  where
    wait :: Int -> IO (Maybe ExitCode)
    wait 0 = return Nothing
    wait count = do
      code <- getExitCode prc
      case code of
        Just a -> return $ Just a
        Nothing -> do
          sleep 0.1
          wait $ count - 1

quitNvim :: Internal.Config e -> NvimProc -> IO ()
quitNvim testCfg prc = do
  quitThread <- async $ runNeovimThunk testCfg quit
  result <- waitQuit prc
  case result of
    Just _ -> return ()
    Nothing -> killProcess prc
  cancel quitThread
  where
    quit = vim_command "qall!"

shutdownNvim :: Internal.Config e -> NvimProc -> IO () -> IO ()
shutdownNvim _ prc stopEventHandlers = do
  stopEventHandlers
  killProcess prc
  -- quitNvim testCfg prc

runTest :: TestConfig -> Internal.Config (Ribosome e) -> Ribo e () -> IO () -> IO ()
runTest TestConfig{..} testCfg thunk _ = do
  result <- race (sleepW tcTimeout) (runNeovimThunk testCfg thunk)
  case result of
    Right _ -> return ()
    Left _ -> fail $ "test exceeded timeout of " ++ show tcTimeout ++ " seconds"

runEmbeddedNvim :: TestConfig -> Ribosome e -> Ribo e () -> NvimProc -> IO ()
runEmbeddedNvim conf ribo thunk prc = do
  nvimConf <- Internal.newConfig (pure Nothing) newRPCConfig
  let testCfg = Internal.retypeConfig ribo nvimConf
  bracket (startHandlers prc conf nvimConf) (shutdownNvim testCfg prc) (runTest conf testCfg thunk)

runEmbedded :: TestConfig -> Ribosome e -> Ribo e () -> IO ()
runEmbedded conf ribo thunk = do
  let pc = testNvimProcessConfig conf
  withProcess pc $ runEmbeddedNvim conf ribo thunk

unsafeEmbeddedSpec :: Runner (Ribosome e) -> TestConfig -> e -> Ribo e () -> IO ()
unsafeEmbeddedSpec runner conf env spec = do
  internal <- newInternalTVar
  let ribo = Ribosome (tcPluginName conf) internal env
  runEmbedded conf ribo $ runner conf spec

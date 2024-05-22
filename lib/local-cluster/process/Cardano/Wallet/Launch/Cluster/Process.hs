{-# LANGUAGE TupleSections #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Evaluate" #-}

module Cardano.Wallet.Launch.Cluster.Process
    ( withLocalCluster
    , withFile
    , EnvVars (..)
    , defaultEnvVars

      -- * Re-exports
    , RunMonitorQ (..)
    , RunFaucetQ (..)
    ) where

import Prelude

import Cardano.BM.ToTextTracer
    ( ToTextTracer (..)
    , newToTextTracer
    )
import Cardano.Launcher
    ( Command (..)
    , IfToSendSigINT (..)
    , StdStream (..)
    , TimeoutInSecs (..)
    , withBackendProcess
    )
import Cardano.Wallet.Launch.Cluster
    ( FaucetFunds
    , FileOf (..)
    )
import Cardano.Wallet.Launch.Cluster.Faucet.Serialize
    ( saveFunds
    )
import Cardano.Wallet.Launch.Cluster.Http.Faucet.Client
    ( RunFaucetQ (..)
    )
import Cardano.Wallet.Launch.Cluster.Http.Monitor.Client
    ( RunMonitorQ (..)
    )
import Cardano.Wallet.Launch.Cluster.Http.Service
    ( withServiceClient
    )
import Cardano.Wallet.Network.Ports
    ( PortNumber
    , getRandomPort
    )
import Cardano.Wallet.Primitive.NetworkId
    ( NetworkId (..)
    , withSNetworkId
    )
import Control.Exception
    ( SomeException (..)
    , catch
    , throwIO
    )
import Control.Monad
    ( forM_
    )
import Control.Monad.Cont
    ( ContT (..)
    )
import Control.Monad.IO.Class
    ( MonadIO (..)
    )
import Control.Tracer
    ( nullTracer
    )
import System.Directory
    ( createDirectoryIfMissing
    )
import System.Environment
    ( lookupEnv
    )
import System.FilePath
    ( takeDirectory
    , (<.>)
    , (</>)
    )
import System.IO
    ( BufferMode (NoBuffering)
    , Handle
    , IOMode (WriteMode)
    , hClose
    , hSetBuffering
    , openFile
    )
import System.IO.Extra
    ( withTempFile
    )
import System.Path
    ( absFile
    )

data EnvVars = EnvVars
    { clusterConfigsPath :: String
    , clusterLogsFilePath :: String
    , clusterLogsMinSeverity :: String
    }

defaultEnvVars :: EnvVars
defaultEnvVars =
    EnvVars
        { clusterConfigsPath = "LOCAL_CLUSTER_CONFIGS"
        , clusterLogsFilePath = "CLUSTER_LOGS_DIR_PATH"
        , clusterLogsMinSeverity = "CLUSTER_LOGS_MIN_SEVERITY"
        }

getClusterConfigsPathFromEnv :: EnvVars -> IO FilePath
getClusterConfigsPathFromEnv environmentVars = do
    mp <- lookupEnv $ clusterConfigsPath environmentVars
    case mp of
        Just path -> pure path
        Nothing -> error "LOCAL_CLUSTER_CONFIGS not set"

getClusterLogsFilePathFromEnv :: EnvVars -> IO (Maybe FilePath)
getClusterLogsFilePathFromEnv environmentVars = do
    mp <- lookupEnv $ clusterLogsFilePath environmentVars
    forM_ mp $ \dir ->
        createDirectoryIfMissing True dir
    pure mp

getClusterLogsMinSeverity :: EnvVars -> IO (Maybe String)
getClusterLogsMinSeverity environmentVars =
    lookupEnv $ clusterLogsMinSeverity environmentVars

-- | A withFile function that creates the directory if it doesn't exist,
-- and sets the buffering to NoBuffering. It also catches exceptions and
-- closes the handle before rethrowing the exception.
-- This cover also a problem with the original withFile function that
-- replace any exception happening in the action with a generic
-- "withFile: openFile: does not exist"
withFile :: FilePath -> IOMode -> (Handle -> IO a) -> IO a
withFile path mode action = do
    createDirectoryIfMissing True (takeDirectory path)
    h <- openFile path mode
    hSetBuffering h NoBuffering
    catch
        (action h)
        $ \(SomeException e) -> do
            hClose h
            throwIO e

-- | Start a local cluster with the given name and initial faucet funds.
-- The cluster will be started in the background and the function will return
-- a pair of functions to query the cluster and a tracer to log as the process
withLocalCluster
    :: FilePath
    -- ^ name of the cluster
    -> EnvVars
    -- ^ environment variables that have to be used
    -> FaucetFunds
    -- ^ initial faucet funds
    -> ContT () IO ((RunMonitorQ IO, RunFaucetQ IO), ToTextTracer)
withLocalCluster name envs faucetFundsValue = do
    port <- liftIO getRandomPort
    faucetFundsPath <- ContT withTempFile
    liftIO $ saveFunds (FileOf $ absFile faucetFundsPath) faucetFundsValue
    (logsPathName, command) <-
        localClusterCommand name envs port faucetFundsPath
    ToTextTracer processLogs <- case logsPathName of
        Nothing -> pure $ ToTextTracer nullTracer
        Just path ->
            ContT
                $ newToTextTracer
                    (path <> "-process" <.> "log")
                    Nothing
    _ <-
        ContT
            $ withBackendProcess
                processLogs
                command
                NoTimeout
                DoNotSendSigINT
    queries <- withSNetworkId (NTestnet 42)
        $ \network -> withServiceClient network port nullTracer
    pure (queries, ToTextTracer processLogs)

-- | Generate a command to start a local cluster with the given the local cluster
-- name, monitoring port, and faucet funds path.
localClusterCommand
    :: FilePath
    -- ^ filename to append to the logs dir
    -> EnvVars
    -- ^ environment variables that have to be used
    -> PortNumber
    -- ^ monitoring port
    -> FilePath
    -- ^ faucet funds path
    -> ContT r IO (Maybe FilePath, Command)
localClusterCommand name envs port faucetFundsPath = do
    configsPath <- liftIO $ getClusterConfigsPathFromEnv envs
    mLogsPath <- liftIO $ getClusterLogsFilePathFromEnv envs
    mMinSeverity <- liftIO $ getClusterLogsMinSeverity envs
    (clusterStdout, logsPathName) <- case mLogsPath of
        Nothing -> pure (NoStream, Nothing)
        Just logsPath -> do
            let logsPathName = logsPath </> name
            fmap (\h -> (UseHandle h, Just logsPathName))
                $ ContT
                $ withFile (logsPath </> name <> "-stdout" <.> "log") WriteMode

    pure
        $ (logsPathName,)
        $ Command
            { cmdName = "local-cluster"
            , cmdArgs =
                [ "--faucet-funds"
                , faucetFundsPath
                , "--monitoring-port"
                , show port
                , "--cluster-configs"
                , configsPath
                ]
                    <> case mLogsPath of
                        Nothing -> []
                        Just logsPath ->
                            [ "--cluster-logs"
                            , logsPath </> name <.> "log"
                            ]
                    <> case mMinSeverity of
                        Nothing -> []
                        Just minSeverity ->
                            [ "--min-severity"
                            , show minSeverity
                            ]
            , cmdSetup = pure ()
            , cmdInput = NoStream
            , cmdOutput = clusterStdout
            }

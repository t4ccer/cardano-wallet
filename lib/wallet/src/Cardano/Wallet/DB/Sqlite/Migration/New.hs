{-# LANGUAGE DataKinds #-}

module Cardano.Wallet.DB.Sqlite.Migration.New
    ( -- * Specific migrations
      newStyleMigrations
    , latestVersion
    , runNewStyleMigrations

      -- * Operating on database
    , newMigrationInterface
    ) where

import Prelude hiding
    ( id
    , (.)
    )

import Cardano.DB.Sqlite
    ( DBHandle (..)
    , DBLog
    , ReadDBHandle
    , withDBHandle
    )
import Cardano.Wallet.DB.Migration
    ( Migration
    , MigrationInterface (..)
    , Version (..)
    , getTargetVersion
    , hoistMigration
    , runMigrations
    )
import Cardano.Wallet.DB.Sqlite.Migration.Old
    ( getSchemaVersion
    , putSchemaVersion
    )
import Cardano.Wallet.DB.Store.Checkpoints.Migration
    ( migratePrologue
    )
import Control.Category
    ( (.)
    )
import Control.Monad.Reader
    ( withReaderT
    )
import Control.Tracer
    ( Tracer
    )
import Database.Persist.Sqlite
    ( SqlPersistT
    )
import Database.Sqlite
    ( Connection
    )
import System.Directory
    ( copyFile
    )

import qualified Cardano.Wallet.DB.Sqlite.Migration.Old as Old
import qualified Cardano.Wallet.DB.Store.Delegations.Migrations.V3.Migration as V3
import qualified Cardano.Wallet.DB.Store.Delegations.Migrations.V5.Migration as V5

{-----------------------------------------------------------------------------
    Specific migrations
------------------------------------------------------------------------------}

newStyleMigrations :: Migration (ReadDBHandle IO) 2 5
newStyleMigrations =
    V5.migrateDelegations
        . migratePrologue
        . V3.migrateDelegations

latestVersion :: Version
latestVersion = getTargetVersion newStyleMigrations

runNewStyleMigrations :: Tracer IO DBLog -> FilePath -> IO ()
runNewStyleMigrations tr fp =
    runMigrations (newMigrationInterface tr) fp newStyleMigrations

_useSqlBackend
    :: Migration (SqlPersistT m) from to
    -> Migration (ReadDBHandle m) from to
_useSqlBackend = hoistMigration $ withReaderT dbBackend

{-----------------------------------------------------------------------------
    Migration Interface
------------------------------------------------------------------------------}

newMigrationInterface
    :: Tracer IO DBLog
    -> MigrationInterface IO DBHandle
newMigrationInterface tr =
    MigrationInterface
        { backupDatabaseFile = \fp v -> do
            let backupFile = fp <> ".v" <> show v <> ".bak"
            copyFile fp backupFile
        , withDatabaseFile = withDBHandle tr
        , getVersion = getVersionNew . dbConn
        , setVersion = setVersionNew . dbConn
        }

oldToNewSchemaVersion :: Old.SchemaVersion -> Version
oldToNewSchemaVersion (Old.SchemaVersion v) = Version v

newToOldSchemaVersion :: Version -> Old.SchemaVersion
newToOldSchemaVersion (Version v) = Old.SchemaVersion v

getVersionNew :: Connection -> IO Version
getVersionNew = fmap oldToNewSchemaVersion . getSchemaVersion

setVersionNew :: Connection -> Version -> IO ()
setVersionNew conn = putSchemaVersion conn . newToOldSchemaVersion

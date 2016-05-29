module Network.Nats.Types
    ( NatsApp 
    , NatsURI
    , NatsConnection (..)
    , NatsSettings (..)
    , defaultSettings
    ) where

import Control.Concurrent.STM (TQueue)
import Data.Conduit.Network

import Data.ByteString (ByteString)

-- | Type alias. A NatsApp is an IO action taking a Nats connection
-- and returning a type a.
type NatsApp a = (NatsConnection -> IO a)

-- | Type alias. URI to specify NATS connection.
type NatsURI = ByteString

-- | The context needed to maintain one NATS connection. Content is opaque
-- to the user.
data NatsConnection = NatsConnection
    { appData  :: !AppData
      -- ^ Stuff gotten from the TCP client, e.g. the source and sink
      -- network conduits.
    , settings :: !NatsSettings
      -- ^ The user provided settings for establishing the connection.
    , txQueue  :: !(TQueue ByteString)
      -- ^ The queue of data (as ByteStrings) to be transmitted.
    }

-- | User specified settings for a NATS connection.
data NatsSettings = NatsSettings
    { verbose  :: !Bool
      -- ^ Turns on +OK protocol acknowledgements.
    , pedantic :: !Bool
      -- ^ Turns on additional strict format checking, e.g.
      -- properly formed subjects.
    } deriving Show

-- | Default NATS settings.
defaultSettings :: NatsSettings
defaultSettings =
    NatsSettings
        { verbose  = False
        , pedantic = False
        }


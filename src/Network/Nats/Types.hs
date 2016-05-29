module Network.Nats.Types
    ( NatsApp 
    , NatsURI
    , NatsConnection (..)
    , NatsException (..)
    , NatsSettings (..)
    , defaultSettings
    ) where

import Control.Concurrent.STM (TQueue)
import Control.Exception (Exception)
import Data.Conduit.Network (AppData)
import Data.ByteString (ByteString)
import Data.Typeable (Typeable)

import Network.Nats.Message (ProtocolError)

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

-- | Exception to be thrown from the Nats client.
data NatsException = NatsException !ProtocolError
    deriving (Typeable, Show)

instance Exception NatsException

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


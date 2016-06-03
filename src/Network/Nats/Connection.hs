module Network.Nats.Connection
    ( Connection (..)
    , Settings (..)
    , defaultSettings
    ) where

import Control.Concurrent.STM (TVar, TQueue)
import Data.ByteString (ByteString)
import Data.Conduit.Network (AppData)

import Network.Nats.Subscriber (Subscribers)

-- | The context needed to maintain one NATS connection. Content is opaque
-- to the user.
data Connection = Connection
    { appData     :: !AppData
      -- ^ Stuff gotten from the TCP client, e.g. the source and sink
      -- network conduits.
    , settings    :: !Settings
      -- ^ The user provided settings for establishing the connection.
    , txQueue     :: !(TQueue ByteString)
      -- ^ The queue of data (as ByteStrings) to be transmitted.

    , subscribers :: !(TVar Subscribers)
      -- ^ The map of subscribers.
    }

-- | User specified settings for a NATS connection.
data Settings = Settings
    { verbose  :: !Bool
      -- ^ Turns on +OK protocol acknowledgements.
    , pedantic :: !Bool
      -- ^ Turns on additional strict format checking, e.g.
      -- properly formed subjects.
    } deriving Show

-- | Default NATS settings.
defaultSettings :: Settings
defaultSettings = 
    Settings
        { verbose  = False
        , pedantic = False
        }



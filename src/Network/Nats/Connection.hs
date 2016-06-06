module Network.Nats.Connection
    ( Connection (..)
    , Settings (..)
    , defaultSettings
    ) where

import Control.Concurrent (MVar)
import Control.Concurrent.STM (TVar, TQueue)
import Data.ByteString (ByteString)
import Data.Conduit.Network (AppData)

import Network.Nats.Logger (LoggerSpec (..), Logger)
import Network.Nats.Subscriber (Subscribers)

-- | The context needed to maintain one NATS connection. Content is opaque
-- to the user.
data Connection = Connection
    { appData     :: !AppData
      -- ^ Stuff gotten from the TCP client, e.g. the source and sink
      -- network conduits.

    , startUpSync :: !(MVar ())
      -- ^ After setting up the pipelines the threads must be
      -- synchronized such that the NatsApp must wait for the Info
      -- message to have been processed and the Connect message have
      -- been queueed.

    , settings    :: !Settings
      -- ^ The user provided settings for establishing the connection.

    , txQueue     :: !(TQueue ByteString)
      -- ^ The queue of data (as ByteStrings) to be transmitted.

    , subscribers :: !(TVar Subscribers)
      -- ^ The map of subscribers.

    , inpLogger   :: Logger
      -- ^ The logger of input messages.

    , outpLogger  :: Logger
      -- ^ The logger of output messages.

    , logCleanUp  :: IO ()
      -- ^ The logger clean up action, flushing buffers etc.
    }

-- | User specified settings for a NATS connection.
data Settings = Settings
    { verbose    :: !Bool
      -- ^ Turns on +OK protocol acknowledgements.
    , pedantic   :: !Bool
      -- ^ Turns on additional strict format checking, e.g.
      -- properly formed subjects.
    , loggerSpec :: !LoggerSpec
    } deriving Show

-- | Default NATS settings.
defaultSettings :: Settings
defaultSettings =
    Settings
        { verbose    = False
        , pedantic   = False
        , loggerSpec = NoLogger
        }



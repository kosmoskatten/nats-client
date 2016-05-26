module Network.Nats.Message
    ( Message (..)
    ) where

import Data.ByteString.Char8 (ByteString)

-- | The kind of messages that can be exchanged between the NATS server
-- and a NATS client.
data Message =
    -- | As soon as the server accepts a connection from the client, it
    -- will send information about itself and the configuration and
    -- security requirements that are necessary for the client to
    -- successfully authenticate with the server and
    -- exchange messages.
    Info { serverId           :: !(Maybe ByteString)
           -- ^ The unique identifier of the NATS server.
         , serverVersion      :: !(Maybe ByteString)
           -- ^ The version of the NATS server.
         , goVersion          :: !(Maybe ByteString)
           -- ^ The version of golang the server was built with.
         , serverHost         :: !(Maybe ByteString)
           -- ^ The IP address of the NATS server host.
         , serverPort         :: !(Maybe Int)
           -- ^ The port number the NATS server is configured to listen on.
         , serverAuthRequired :: !(Maybe Bool)
           -- ^ If set, the client should try to authenticate.
         , serverSslRequired  :: !(Maybe Bool)
           -- ^ If set, the client must authenticate using SSL.
         , serverTlsRequired  :: !(Maybe Bool)
         , serverTlsVerify    :: !(Maybe Bool)
         , maxPayload         :: !(Maybe Int)
           -- ^ Maximum payload size that server will accept from client.
         }

    -- | The Connect message is analogous to the Info message. Once the
    -- client has established a TCP/IP socket connection with the NATS
    -- server, and an Info message has been received from the server,
    -- the client may sent a Connect message to the NATS server to
    -- provide more information about the current connection as
    -- well as security information.
  | Connect { clientVerbose :: !(Maybe Bool) }
    deriving (Eq, Show)

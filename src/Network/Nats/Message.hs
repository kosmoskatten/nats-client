module Network.Nats.Message
    ( ProtocolError (..)
    , Message (..)
    ) where

import Data.ByteString.Char8 (ByteString)

-- | Protocol error enumeration.
data ProtocolError =
    UnknownProtocolOperation
  | AuthorizationViolation
  | AuthorizationTimeout
  | ParserError
  | StaleConnection
  | SlowConsumer
  | MaximumPayloadExceeded
  | InvalidSubject
    deriving (Bounded, Enum, Eq, Show)

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
  | Connect { clientVerbose     :: !(Maybe Bool)
              -- ^ Turns on +OK protocol acknowledgements.
            , clientPedantic    :: !(Maybe Bool)
              -- ^ Turns on additional strict format checking.
            , clientSslRequired :: !(Maybe Bool)
              -- ^ Indicates whether the client requires an SSL connection.
            , clientAuthToken   :: !(Maybe ByteString)
              -- ^ Client authorization token.
            , clientUser        :: !(Maybe ByteString)
              -- ^ Connection username (if auth_required is set).
            , clientPass        :: !(Maybe ByteString)
              -- ^ Connection password (if auth_required is set).
            , clientName        :: !(Maybe ByteString)
              -- ^ Optional client name.
            , clientLang        :: !(Maybe ByteString)
              -- The implementation of the client.
            , clientVersion     :: !(Maybe ByteString)
              -- ^ The version of the client.
            }

    -- | When the verbose (clientVerbose) option is set to true, the
    -- server acknowledges each well-formed prototol message from the
    -- client with a +OK message.
  | Ok

    -- | The -ERR message is used by the server indicate a protocol,
    -- authorization, or other runtime connection error to the client.
    -- Most of those errors result in the server closing the
    -- connection. InvalidSubject is the exception.
  | Err !ProtocolError
    deriving (Eq, Show)

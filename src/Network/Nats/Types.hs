{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric  #-}
module Network.Nats.Types
    ( Topic
    , Payload
    , QueueGroup
    , NatsURI
    , NatsException (..)
    , ProtocolError (..)
    , Timeout (..)
    , isFatalError
    , toUSec
    ) where

import Control.DeepSeq (NFData)
import Control.Exception (Exception)
import Data.Typeable (Typeable)
import GHC.Generics (Generic)

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS

type Topic = BS.ByteString
type Payload = LBS.ByteString
type QueueGroup = BS.ByteString

-- | Type alias. URI to specify NATS connection.
type NatsURI = BS.ByteString

-- | Exception to be thrown from the Nats client.
data NatsException = NatsException !ProtocolError
    deriving (Typeable, Show)

instance Exception NatsException

-- | Protocol error enumeration.
data ProtocolError
  = UnknownProtocolOperation
  | AuthorizationViolation
  | AuthorizationTimeout
  | ParserError
  | StaleConnection
  | SlowConsumer
  | MaximumPayloadExceeded
  | InvalidSubject
    deriving (Bounded, Enum, Eq, Generic, NFData, Show)

-- | A value to specify timeout duration.
data Timeout
    = Sec  !Int
    | MSec !Int
    | USec !Int
    | Infinity
    deriving Show

-- | Tell if a protocol error is fatal or not. Fatal is an error that
-- will make the server close the connection. All protocol errors but
-- InvalidSubject are fatal.
isFatalError :: ProtocolError -> Bool
isFatalError InvalidSubject = False
isFatalError _              = True

-- | Convert a Timeout to microseconds, which is the unit for
-- System.Timeout.timeout.
toUSec :: Timeout -> Int
toUSec (Sec d)  = d * 1000000
toUSec (MSec d) = d * 1000
toUSec (USec d) = d
toUSec Infinity = -1


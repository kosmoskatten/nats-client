module Network.Nats.Message
    ( Message (..)
    ) where

import Data.ByteString.Char8 (ByteString)

data Message =
    Info { serverId           :: !(Maybe ByteString)
         , serverVersion      :: !(Maybe ByteString)
         , goVersion          :: !(Maybe ByteString)
         , serverHost         :: !(Maybe ByteString)
         , serverPort         :: !(Maybe Int)
         , serverAuthRequired :: !(Maybe Bool)
         , serverSslRequired  :: !(Maybe Bool)
         , maxPayload         :: !(Maybe Int)
         }
    deriving (Eq, Show)

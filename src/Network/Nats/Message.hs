module Network.Nats.Message
    ( Message (..)
    ) where

import Data.ByteString.Char8 (ByteString)

data Message =
    Info { serverId      :: !(Maybe ByteString)
         , serverVersion :: !(Maybe ByteString)
         , goVersion     :: !(Maybe ByteString)
         }
    deriving Show

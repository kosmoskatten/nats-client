module Network.Nats.Message
    ( Message (..)
    ) where

import Data.ByteString.Char8 (ByteString)

data Message =
    Info { serverId      :: !ByteString
         , serverVersion :: !ByteString
         }
    deriving Show

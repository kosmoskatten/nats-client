{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
module Network.Nats.Builder
    ( buildMessage
    ) where

import Data.ByteString (ByteString)
import Data.ByteString.Builder
import Data.Monoid ((<>))
import Data.List (foldl', intersperse)

import Network.Nats.Message (Message (..))

class Buildable a where
    build :: a -> Builder

instance Buildable Bool where
    build False = byteString "false"
    build True  = byteString "true"

instance Buildable Int where
    build = intDec

instance Buildable ByteString where
    build value = charUtf8 '\"' <> byteString value <> charUtf8 '\"'

-- | Translate a Message record to a Builder. The building of handshake
-- messages are not optimized for speed :-)
buildMessage :: Message -> Builder
buildMessage Info {..} =
    let fields = foldl' handshakeMessageField [] 
                        [ ("\"server_id\"", serverId)
                        ]
        fields' = intersperse (charUtf8 ',') $ reverse fields
    in mconcat $ byteString "INFO {":(fields' ++ [charUtf8 '}'])

handshakeMessageField :: Buildable a => [Builder] 
                      -> (ByteString, Maybe a) 
                      -> [Builder]
handshakeMessageField xs (field, (Just value)) =
    let x = byteString field <> charUtf8 ':' <> build value
    in x:xs
handshakeMessageField xs (_, Nothing) = xs

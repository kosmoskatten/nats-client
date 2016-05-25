{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
module Network.Nats.Builder
    ( buildMessage
    ) where

import Data.ByteString (ByteString)
import Data.ByteString.Builder
import Data.Monoid ((<>))

import Network.Nats.Message (Message (..))

-- | Translate a Message record to a Builder.
buildMessage :: Message -> Builder
buildMessage msg@Info {..} =
    byteString "INFO {" <>
    charUtf8 '}'

handshakeMessageField :: ByteString -> a -> Builder
handshakeMessageField = undefined

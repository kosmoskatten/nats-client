{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE RecordWildCards           #-}
module Network.Nats.Writer
    ( writeMessage
    ) where

import Data.ByteString (ByteString)
import Data.ByteString.Builder
import Data.Monoid ((<>))
import Data.List (foldl', intersperse)

import qualified Data.ByteString.Lazy as LBS

import Network.Nats.Message (Message (..))
import Network.Nats.Types (ProtocolError (..), SubscriptionId (..))

-- | Existentially quantified Field type, to allow for a polymorph
-- list of Fields. All fields with the contraint of beeing Writeable.
data Field = forall w. Writeable w => Field !w

-- | Helper class used for the writing of "handshake message" fields.
class Writeable w where
    write :: w -> Builder

-- | Instance for Bool.
instance Writeable Bool where
    write False = byteString "false"
    write True  = byteString "true"

-- | Instance for Int.
instance Writeable Int where
    write = intDec

-- | Instance for ByteString.
instance Writeable ByteString where
    write value = charUtf8 '\"' <> byteString value <> charUtf8 '\"'

-- | Translate a Message value to a lazy ByteString.
writeMessage :: Message -> LBS.ByteString
writeMessage = toLazyByteString . writeMessage'

-- | Translate a Message value to a Builder.
writeMessage' :: Message -> Builder

-- The first of the handshake messages; Info.
writeMessage' Info {..} =
    let fields = foldl' writeField [] 
                   [ ("\"server_id\"", Field <$> serverId)
                   , ("\"version\"", Field <$> serverVersion)
                   , ("\"go\"", Field <$> goVersion)
                   , ("\"host\"", Field <$> serverHost)
                   , ("\"port\"", Field <$> serverPort)
                   , ("\"auth_required\"", Field <$> serverAuthRequired)
                   , ("\"ssl_required\"", Field <$> serverSslRequired)
                   , ("\"tls_required\"", Field <$> serverTlsRequired)
                   , ("\"tls_verify\"", Field <$> serverTlsVerify)
                   , ("\"max_payload\"", Field <$> maxPayload)
                   ]
        fields' = intersperse (charUtf8 ',') $ reverse fields
    in mconcat $ byteString "INFO {":(fields' ++ [charUtf8 '}'])

-- The second of the handshake messages; Connect.
writeMessage' Connect {..} =
    let fields = foldl' writeField []
                   [ ("\"verbose\"", Field <$> clientVerbose)
                   , ("\"pedantic\"", Field <$> clientPedantic)
                   , ("\"ssl_required\"", Field <$> clientSslRequired)
                   , ("\"auth_token\"", Field <$> clientAuthToken)
                   , ("\"user\"", Field <$> clientUser)
                   , ("\"pass\"", Field <$> clientPass)
                   , ("\"name\"", Field <$> clientName)
                   , ("\"lang\"", Field <$> clientLang)
                   , ("\"version\"", Field <$> clientVersion)
                   ]
        fields' = intersperse (charUtf8 ',') $ reverse fields
    in mconcat $ byteString "CONNECT {":(fields' ++ [byteString "}\r\n"])

-- Msg message without a reply subject.
writeMessage' (Msg subject sid Nothing payload) =
    byteString "MSG " <> byteString subject <> charUtf8 ' '
                      <> writeSid sid <> charUtf8 ' '
                      <> int64Dec (LBS.length payload) <> byteString "\r\n"
                      <> lazyByteString payload <> byteString "\r\n"

-- Msg message with a reply subject.
writeMessage' (Msg subject sid (Just reply) payload) =
    byteString "MSG " <> byteString subject <> charUtf8 ' '
                      <> writeSid sid <> charUtf8 ' '
                      <> byteString reply <> charUtf8 ' '
                      <> int64Dec (LBS.length payload) <> byteString "\r\n"
                      <> lazyByteString payload <> byteString "\r\n"

-- Pub message without a reply subject.
writeMessage' (Pub subject Nothing payload) =
    byteString "PUB " <> byteString subject <> charUtf8 ' '
                      <> int64Dec (LBS.length payload) <> byteString "\r\n"
                      <> lazyByteString payload <> byteString "\r\n"

-- Pub message with a reply subject.
writeMessage' (Pub subject (Just reply) payload) =
    byteString "PUB " <> byteString subject <> charUtf8 ' '
                      <> byteString reply <> charUtf8 ' '
                      <> int64Dec (LBS.length payload) <> byteString "\r\n"
                      <> lazyByteString payload <> byteString "\r\n"

-- Sub message without a queue group.
writeMessage' (Sub subject Nothing sid) =
    byteString "SUB " <> byteString subject <> charUtf8 ' ' 
                      <> writeSid sid <> byteString "\r\n"

-- Sub message with a queue group.
writeMessage' (Sub subject (Just queue) sid) =
    byteString "SUB " <> byteString subject <> charUtf8 ' '
                      <> byteString queue <> charUtf8 ' '
                      <> writeSid sid <> byteString "\r\n"

-- Server acknowledge of a well-formed message.
writeMessage' Ok = byteString "+OK\r\n"

-- | Server indication of a protocol, authorization, or other
-- runtime connection error.
writeMessage' (Err pe) = byteString "-ERR " <> writePE pe <> "\r\n"

-- | The translate a Field to a Builder and prepend it to the list of
-- Builders.
writeField :: [Builder] -> (ByteString, Maybe Field) -> [Builder]
writeField xs (name, Just (Field value)) = 
    let x = byteString name <> charUtf8 ':' <> write value
    in x:xs

-- There's a Nothing Field. Just return the unmodified Builder list.
writeField xs (_, Nothing) = xs

-- | Translate a ProtocolError to a Builder.
writePE :: ProtocolError -> Builder
writePE UnknownProtocolOperation = byteString "\'Unknown Protocol Operation\'"
writePE AuthorizationViolation   = byteString "\'Authorization Violation\'"
writePE AuthorizationTimeout     = byteString "\'Authorization Timeout\'"
writePE ParserError              = byteString "\'Parser Error\'"
writePE StaleConnection          = byteString "\'Stale Connection\'"
writePE SlowConsumer             = byteString "\'Slow Consumer\'"
writePE MaximumPayloadExceeded   = byteString "\'Maximum Payload Exceeded\'"
writePE InvalidSubject           = byteString "\'Invalid Subject\'"

-- | Translate a SubscriptionId to a Builder.
writeSid :: SubscriptionId -> Builder
writeSid (Sid sid) = byteString sid

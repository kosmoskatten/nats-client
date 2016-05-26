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

import Network.Nats.Message (Message (..))

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

-- | Translate a Message record to a Builder. The building of handshake
-- messages are not optimized for speed :-)
writeMessage :: Message -> Builder

-- The first of the handshake messages; Info.
writeMessage Info {..} =
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
writeMessage Connect {..} =
    let fields = foldl' writeField []
                   [ ("\"verbose\"", Field <$> clientVerbose)
                   ]
        fields' = intersperse (charUtf8 ',') $ reverse fields
    in mconcat $ byteString "CONNECT {":(fields' ++ [byteString "}\r\n"])

-- | The translate a Field to a Builder and prepend it to the list of
-- Builders.
writeField :: [Builder] -> (ByteString, Maybe Field) -> [Builder]
writeField xs (name, Just (Field value)) = 
    let x = byteString name <> charUtf8 ':' <> write value
    in x:xs

-- There's a Nothing Field. Just return the unmodified Builder list.
writeField xs (_, Nothing) = xs

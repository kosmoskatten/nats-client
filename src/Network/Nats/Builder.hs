{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE RecordWildCards           #-}
module Network.Nats.Builder
    ( buildMessage
    ) where

import Data.ByteString (ByteString)
import Data.ByteString.Builder
import Data.Monoid ((<>))
import Data.List (foldl', intersperse)

import Network.Nats.Message (Message (..))

-- | Existentially quantified Field type, to allow for a polymorph
-- list of Fields. All fields with the contraint of beeing Buildable.
data Field = forall b. Buildable b => Field !b

-- | Helper class used for the building of "handshake message" fields.
class Buildable a where
    build :: a -> Builder

-- | Instance for Bool.
instance Buildable Bool where
    build False = byteString "false"
    build True  = byteString "true"

-- | Instance for Int.
instance Buildable Int where
    build = intDec

-- | Instance for ByteString.
instance Buildable ByteString where
    build value = charUtf8 '\"' <> byteString value <> charUtf8 '\"'

-- | Translate a Message record to a Builder. The building of handshake
-- messages are not optimized for speed :-)
buildMessage :: Message -> Builder
buildMessage Info {..} =
    let fields = foldl' buildField [] 
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

-- | The translate a Field to a Builder and prepend it to the list of
-- Builders.
buildField :: [Builder] -> (ByteString, Maybe Field) -> [Builder]
buildField xs (name, Just (Field value)) = 
    let x = byteString name <> charUtf8 ':' <> build value
    in x:xs

-- There's a Nothing Field. Just return the unmodified Builder list.
buildField xs (_, Nothing) = xs

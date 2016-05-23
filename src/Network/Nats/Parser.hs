{-# LANGUAGE OverloadedStrings #-}
module Network.Nats.Parser
    (
    ) where

import Control.Applicative ((<|>))
import Control.Monad (void)
import Data.Attoparsec.ByteString.Char8
import Data.ByteString.Char8 (ByteString)

import qualified Data.ByteString.Char8 as BS

import Network.Nats.Message (Message (..))

data HandshakeMessageValue =
    Bool   !Bool
  | String !ByteString
  | Int    !Int
    deriving Show

type HandshakeMessageField = (ByteString, HandshakeMessageValue)

-- | The parsing of the info message is not performance critical.
infoMessage :: Parser Message
infoMessage = do
    void $ many' space
    void $ stringCI "info"
    void $ space
    void $ char '{'
    _fields <- parseInfoMessageFields
    void $ char '}'
    return Info { serverId = "test", serverVersion = "test" }

parseInfoMessageFields :: Parser [HandshakeMessageField]
parseInfoMessageFields = infoMessageField `sepBy` (char ',')
    where
      infoMessageField = parseServerId
                     <|> parseServerVersion

parseServerId :: Parser HandshakeMessageField
parseServerId = do
    void $ string "\"server_id\""
    void $ char ':'
    value <- quotedString
    return ("server_id", String value)

parseServerVersion :: Parser HandshakeMessageField
parseServerVersion = do
    void $ string "\"version\""
    void $ char ':'
    value <- quotedString
    return ("version", String value)

quotedString :: Parser ByteString
quotedString = BS.pack <$> (char '\"' *> manyTill anyChar (char '\"'))

boolean :: Parser Bool
boolean = string "false" *> return False <|> string "true" *> return True

handshakeFieldWithDefault :: ByteString -> HandshakeMessageValue
                          -> [HandshakeMessageField] 
                          -> HandshakeMessageValue
handshakeFieldWithDefault key def fields =
    maybe def id $ lookup key fields


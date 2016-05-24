{-# LANGUAGE OverloadedStrings #-}
module Network.Nats.Parser
    ( message
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

message :: Parser Message
message = infoMessage

-- | The parsing of the info message is not performance critical.
infoMessage :: Parser Message
infoMessage = do
    void $ many' space
    void $ stringCI "info"
    void $ space
    void $ char '{'
    fields <- parseInfoMessageFields
    void $ char '}'
    mkInfoMessage fields

parseInfoMessageFields :: Parser [HandshakeMessageField]
parseInfoMessageFields = infoMessageField `sepBy` (char ',')
    where
      infoMessageField = parseServerId
                     <|> parseServerVersion
                     <|> parseGoVersion

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

parseGoVersion :: Parser HandshakeMessageField
parseGoVersion = do
    void $ string "\"go\""
    void $ char ':'
    value <- quotedString
    return ("go", String value)

quotedString :: Parser ByteString
quotedString = BS.pack <$> (char '\"' *> manyTill anyChar (char '\"'))

boolean :: Parser Bool
boolean = string "false" *> return False <|> string "true" *> return True

mkInfoMessage :: [HandshakeMessageField] -> Parser Message
mkInfoMessage fields = do
    Info <$> (asByteString $ lookup "server_id" fields)
         <*> (asByteString $ lookup "version" fields)
         <*> (asByteString $ lookup "go" fields)

asByteString :: Maybe HandshakeMessageValue -> Parser (Maybe ByteString)
asByteString Nothing               = return Nothing
asByteString (Just (String value)) = return (Just value)
asByteString _                     = fail "Expected a ByteString"

asBool :: Maybe HandshakeMessageValue -> Parser (Maybe Bool)
asBool Nothing             = return Nothing
asBool (Just (Bool value)) = return (Just value)
asBool _                   = fail "Expected a boolean"

asInt :: Maybe HandshakeMessageValue -> Parser (Maybe Int)
asInt Nothing            = return Nothing
asInt (Just (Int value)) = return (Just value)
asInt _                  = fail "Expected an Int"


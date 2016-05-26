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
message = infoMessage <|> connectMessage

-- | The parsing of the Info message is not performance critical.
infoMessage :: Parser Message
infoMessage = do
    void $ many' space
    void $ stringCI "info"
    void space
    void $ char '{'
    fields <- parseInfoMessageFields
    void $ char '}'
    mkInfoMessage fields

parseInfoMessageFields :: Parser [HandshakeMessageField]
parseInfoMessageFields = infoMessageField `sepBy` char ','
    where
      infoMessageField = parseServerId
                     <|> parseServerVersion
                     <|> parseGoVersion
                     <|> parseServerHost
                     <|> parseServerPort
                     <|> parseServerAuthRequired
                     <|> parseSslRequired
                     <|> parseTlsRequired
                     <|> parseTlsVerify
                     <|> parseMaxPayload

-- | Nor is the parsing the Connect message performace critical.
connectMessage :: Parser Message
connectMessage = do
    void $ many' space
    void $ stringCI "connect"
    void space
    void $ char '{'
    fields <- parseConnectMessageFields
    void $ char '}'
    mkConnectMessage fields

parseConnectMessageFields :: Parser [HandshakeMessageField]
parseConnectMessageFields = connectMessageField `sepBy` char ','
    where
      connectMessageField = parseClientVerbose
                        <|> parseClientPedantic 

parseServerId :: Parser HandshakeMessageField
parseServerId = pair "\"server_id\"" quotedString "server_id" String

parseServerVersion :: Parser HandshakeMessageField
parseServerVersion = pair "\"version\"" quotedString "version" String

parseGoVersion :: Parser HandshakeMessageField
parseGoVersion = pair "\"go\"" quotedString "go" String

parseServerHost :: Parser HandshakeMessageField
parseServerHost = pair "\"host\"" quotedString "host" String

parseServerPort :: Parser HandshakeMessageField
parseServerPort = pair "\"port\"" decimal "port" Int

parseServerAuthRequired :: Parser HandshakeMessageField
parseServerAuthRequired = 
    pair "\"auth_required\"" boolean "auth_required" Bool

parseSslRequired :: Parser HandshakeMessageField
parseSslRequired = pair "\"ssl_required\"" boolean "ssl_required" Bool

parseTlsRequired :: Parser HandshakeMessageField
parseTlsRequired = pair "\"tls_required\"" boolean "tls_required" Bool

parseTlsVerify :: Parser HandshakeMessageField
parseTlsVerify = pair "\"tls_verify\"" boolean "tls_verify" Bool

parseMaxPayload :: Parser HandshakeMessageField
parseMaxPayload = pair "\"max_payload\"" decimal "max_payload" Int

parseClientVerbose :: Parser HandshakeMessageField
parseClientVerbose = pair "\"verbose\"" boolean "verbose" Bool

parseClientPedantic :: Parser HandshakeMessageField
parseClientPedantic = pair "\"pedantic\"" boolean "pedantic" Bool

pair :: ByteString -> Parser a -> ByteString 
               -> (a -> HandshakeMessageValue) 
               -> Parser HandshakeMessageField
pair fieldName parser keyName ctor = do
    void $ string fieldName
    void $ char ':'
    value <- parser
    return (keyName, ctor value)

quotedString :: Parser ByteString
quotedString = BS.pack <$> (char '\"' *> manyTill anyChar (char '\"'))

boolean :: Parser Bool
boolean = string "false" *> return False <|> string "true" *> return True

mkInfoMessage :: [HandshakeMessageField] -> Parser Message
mkInfoMessage fields =
    Info <$> asByteString (lookup "server_id" fields)
         <*> asByteString (lookup "version" fields)
         <*> asByteString (lookup "go" fields)
         <*> asByteString (lookup "host" fields)
         <*> asInt (lookup "port" fields)
         <*> asBool (lookup "auth_required" fields)
         <*> asBool (lookup "ssl_required" fields)
         <*> asBool (lookup "tls_required" fields)
         <*> asBool (lookup "tls_verify" fields)
         <*> asInt (lookup "max_payload" fields)

mkConnectMessage :: [HandshakeMessageField] -> Parser Message
mkConnectMessage fields =
    Connect <$> asBool (lookup "verbose" fields)
            <*> asBool (lookup "pedantic" fields)

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


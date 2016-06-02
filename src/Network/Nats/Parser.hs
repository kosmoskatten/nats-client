{-# LANGUAGE OverloadedStrings #-}
module Network.Nats.Parser
    ( parseMessage
    ) where

import Control.Applicative ((<|>))
import Control.Monad (void)
import Data.Attoparsec.ByteString.Char8
import Data.ByteString.Char8 (ByteString)

import qualified Data.Attoparsec.ByteString.Char8 as AP
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy.Char8 as LBS

import Network.Nats.Message (Message (..))
import Network.Nats.Types (ProtocolError (..), SubscriptionId (..))

data HandshakeMessageValue =
    Bool   !Bool
  | String !ByteString
  | Int    !Int
    deriving Show

type HandshakeMessageField = (ByteString, HandshakeMessageValue)

parseMessage :: Parser Message
parseMessage = msgMessage
           <|> infoMessage 
           <|> connectMessage
           <|> pubMessage
           <|> subMessage
           <|> okMessage 
           <|> errMessage

-- | The parsing of the Info message is not performance critical.
infoMessage :: Parser Message
infoMessage = do
    skipSpace
    msgName "INFO"
    singleSpace
    void $ char '{'
    fields <- parseInfoMessageFields
    void $ char '}'
    mkInfoMessage fields

parseInfoMessageFields :: Parser [HandshakeMessageField]
parseInfoMessageFields = infoMessageField `sepBy` char ','
    where
      infoMessageField = parseServerId
                     <|> parseVersion
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
    skipSpace
    msgName "CONNECT"
    singleSpace
    void $ char '{'
    fields <- parseConnectMessageFields
    void $ char '}'
    newLine
    mkConnectMessage fields

parseConnectMessageFields :: Parser [HandshakeMessageField]
parseConnectMessageFields = connectMessageField `sepBy` char ','
    where
      connectMessageField = parseClientVerbose
                        <|> parseClientPedantic
                        <|> parseSslRequired
                        <|> parseClientAuthToken
                        <|> parseClientUser
                        <|> parseClientPass
                        <|> parseClientName
                        <|> parseClientLang
                        <|> parseVersion

msgMessage :: Parser Message
msgMessage = do
    skipSpace
    msgMessageWithReply <|> msgMessageWithoutReply

msgMessageWithReply :: Parser Message
msgMessageWithReply = do
    msgName "MSG"
    singleSpace
    subject <- takeTill isSpace
    singleSpace
    sid <- Sid <$> takeTill isSpace
    singleSpace
    reply <- takeTill isSpace
    singleSpace
    len <- decimal
    newLine
    payload <- LBS.fromStrict <$> AP.take len
    newLine
    return $ Msg subject sid (Just reply) payload

msgMessageWithoutReply :: Parser Message
msgMessageWithoutReply = do
    msgName "MSG"
    singleSpace
    subject <- takeTill isSpace
    singleSpace
    sid <- Sid <$> takeTill isSpace
    singleSpace
    len <- decimal
    newLine
    payload <- LBS.fromStrict <$> AP.take len
    newLine
    return $ Msg subject sid Nothing payload

pubMessage :: Parser Message
pubMessage = do
    skipSpace
    pubMessageWithReply <|> pubMessageWithoutReply

pubMessageWithReply :: Parser Message
pubMessageWithReply = do
    msgName "PUB"
    singleSpace
    subject <- takeTill isSpace
    singleSpace
    reply <- takeTill isSpace
    singleSpace
    len <- decimal
    newLine
    payload <- LBS.fromStrict <$> AP.take len
    newLine
    return $ Pub subject (Just reply) payload

pubMessageWithoutReply :: Parser Message
pubMessageWithoutReply = do
    msgName "PUB"
    singleSpace
    subject <- takeTill isSpace
    singleSpace
    len <- decimal
    newLine
    payload <- LBS.fromStrict <$> AP.take len
    newLine
    return $ Pub subject Nothing payload

subMessage :: Parser Message
subMessage = do
    skipSpace
    subMessageWithQueue <|> subMessageWithoutQueue

subMessageWithQueue :: Parser Message
subMessageWithQueue = do
    msgName "SUB"
    singleSpace
    subject <- takeTill isSpace
    singleSpace
    queue <- takeTill isSpace
    singleSpace
    sid <- Sid <$> takeTill (== '\r')
    newLine
    return $ Sub subject (Just queue) sid
    
subMessageWithoutQueue :: Parser Message
subMessageWithoutQueue = do
    msgName "SUB"
    singleSpace
    subject <- takeTill isSpace
    singleSpace
    sid <- Sid <$> takeTill (== '\r')
    newLine
    return $ Sub subject Nothing sid

okMessage :: Parser Message
okMessage = do
    skipSpace
    msgName "+OK"
    newLine
    return Ok

errMessage :: Parser Message
errMessage = do
    skipSpace
    msgName "-ERR"
    skipSpace
    pe <- protocolError
    newLine
    return $ Err pe

parseServerId :: Parser HandshakeMessageField
parseServerId = pair "\"server_id\"" quotedString "server_id" String

parseVersion :: Parser HandshakeMessageField
parseVersion = pair "\"version\"" quotedString "version" String

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

parseClientAuthToken :: Parser HandshakeMessageField
parseClientAuthToken =
    pair "\"auth_token\"" quotedString "auth_token" String

parseClientUser :: Parser HandshakeMessageField
parseClientUser = pair "\"user\"" quotedString "user" String

parseClientPass :: Parser HandshakeMessageField
parseClientPass = pair "\"pass\"" quotedString "pass" String

parseClientName :: Parser HandshakeMessageField
parseClientName = pair "\"name\"" quotedString "name" String

parseClientLang :: Parser HandshakeMessageField
parseClientLang = pair "\"lang\"" quotedString "lang" String

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

protocolError :: Parser ProtocolError
protocolError =
    stringCI "\'Unknown Protocol Operation\'" 
        *> return UnknownProtocolOperation <|>

    stringCI "\'Authorization Violation\'"
        *> return AuthorizationViolation   <|>

    stringCI "\'Authorization Timeout\'"
        *> return AuthorizationTimeout     <|>

    stringCI "\'Parser Error\'"
        *> return ParserError              <|>

    stringCI "\'Stale Connection\'"
        *> return StaleConnection          <|>

    stringCI "\'Slow Consumer\'"
        *> return SlowConsumer             <|>

    stringCI "\'Maximum Payload Exceeded\'"
        *> return MaximumPayloadExceeded   <|>

    stringCI "\'Invalid Subject\'"
        *> return InvalidSubject

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
            <*> asBool (lookup "ssl_required" fields)
            <*> asByteString (lookup "auth_token" fields)
            <*> asByteString (lookup "user" fields)
            <*> asByteString (lookup "pass" fields)
            <*> asByteString (lookup "name" fields)
            <*> asByteString (lookup "lang" fields)
            <*> asByteString (lookup "version" fields)

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

singleSpace :: Parser ()
singleSpace = void space

newLine :: Parser ()
newLine = void $ string "\r\n"

msgName :: ByteString -> Parser ()
msgName = void . stringCI


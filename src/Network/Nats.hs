{-# LANGUAGE BangPatterns      #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
module Network.Nats
    ( NatsConnection
    , NatsSettings (..)
    , NatsApp
    , NatsURI
    , defaultSettings
    , runNatsClient
    ) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async, cancel, wait)
import Control.Concurrent.STM ( TQueue
                              , atomically
                              , newTQueueIO
                              , readTQueue
                              , writeTQueue
                              )
import Control.Monad.IO.Class (liftIO)
import Data.ByteString (ByteString)
import Data.ByteString.Builder (Builder)
import Data.Conduit
import Data.Conduit.Attoparsec
import Data.Conduit.ByteString.Builder (builderToByteString)
import Data.Conduit.Network

import Network.Nats.Message (Message (..))
import Network.Nats.Parser (message)
import Network.Nats.Writer (writeMessage)

-- | The context needed to maintain one NATS connection. Content is opaque
-- to the user.
data NatsConnection = NatsConnection
    { appData  :: !AppData
      -- ^ Stuff gotten from the TCP client, e.g. the source and sink
      -- network conduits.
    , settings :: !NatsSettings
      -- ^ The user provided settings for establishing the connection.
    , txQueue  :: !(TQueue Builder)
      -- ^ The queue of data (as Builder values) to be transmitted.
    }

-- | User specified settings for a NATS connection.
data NatsSettings = NatsSettings
    { verbose  :: !Bool
      -- ^ Turns on +OK protocol acknowledgements.
    , pedantic :: !Bool
      -- ^ Turns on additional strict format checking, e.g.
      -- properly formed subjects.
    } deriving Show

-- | Type alias. A NatsApp is an IO action taking a Nats connection
-- and returning a type a.
type NatsApp a = (NatsConnection -> IO a)

-- | Type alias. URI to specify NATS connection.
type NatsURI = ByteString

-- | Default NATS settings.
defaultSettings :: NatsSettings
defaultSettings =
    NatsSettings
        { verbose  = False
        , pedantic = False
        }

runNatsClient :: NatsSettings -> NatsURI -> NatsApp a -> IO a
runNatsClient settings' _uri app = do
    let tcpSettings = clientSettings 4222 "localhost"
    runTCPClient tcpSettings $ \appData' -> do
        txQueue' <- newTQueueIO
        let conn = NatsConnection { appData  = appData'
                                  , settings = settings'
                                  , txQueue  = txQueue'
                                  }
        receiver    <- async $ receptionPipeline conn
        transmitter <- async $ transmissionPipeline conn

        result <- app conn
        mapM_ cancel [ receiver, transmitter ]
        mapM_ wait [ receiver, transmitter ]
        return result

-- | Serialize and enqueue a message for sending. The serialization up
-- to and until the production of Builders are performed in the calling
-- thread. The serialization to ByteString is performed by the sender
-- thread.
enqueueMessage :: NatsConnection -> Message -> IO ()
enqueueMessage NatsConnection {..} msg = do
    let !builder = writeMessage msg
    atomically $ writeTQueue txQueue builder

transmissionPipeline :: NatsConnection -> IO ()
transmissionPipeline NatsConnection {..} =
    builderSource =$= builderToByteString $$ byteStringSink
    where
      builderSource :: Source IO Builder
      builderSource = do
          builder <- liftIO $ atomically (readTQueue txQueue)
          liftIO $ print "Got builder"
          yield builder
          builderSource

-- | The reception pipeline. A stream of data from the source (produce
-- ByteStrings from the socket), to the parser (produce messages) and
-- finally to the messageSink and the message handler.
receptionPipeline :: NatsConnection -> IO ()
receptionPipeline conn = do
    let source = appSource $ appData conn
    source =$= conduitParserEither message $$ messageSink
    where
      messageSink :: Sink (Either ParseError (PositionRange, Message)) IO ()
      messageSink = awaitForever $ \eMsg ->
        case eMsg of
            Right (_, msg) -> liftIO $ handleMessage conn msg
            Left err       -> liftIO $ print err
            
-- | Handle the semantic actions for one received message.
handleMessage :: NatsConnection -> Message -> IO ()

-- Handle an Info message. Just produce and enqueue a Connect message.
handleMessage conn@NatsConnection {..} msg@Info {..} =
    enqueueMessage conn $ mkConnectMessage settings msg

handleMessage _conn msg = putStrLn "Got something else."

-- | Given the settings and the Info record, produce a Connect record.
mkConnectMessage :: NatsSettings -> Message -> Message
mkConnectMessage NatsSettings {..} Info {..} =
    Connect { clientVerbose     = Just verbose
            , clientPedantic    = Just pedantic
            , clientSslRequired = Just False
            , clientAuthToken   = Nothing
            , clientUser        = Nothing
            , clientPass        = Nothing
            , clientName        = Just "nats-client"
            , clientLang        = Just "Haskell"
            , clientVersion     = Just "0.1.0.0"
            }
mkConnectMessage _ _ = error "Must be an Info record."

delayApp :: Int -> NatsConnection -> IO ()
delayApp sec _ = threadDelay $ sec * 1000000

byteStringSink :: Sink ByteString IO ()
byteStringSink = awaitForever $ liftIO . print

{-runNatsClient2 :: ByteString -> (NatsConnection -> IO a) -> IO a
runNatsClient2 _ client = do
    let settings = clientSettings 4222 "localhost"
    runTCPClient settings $ \appData' -> do
        let conn = NatsConnection { appData = appData' }
        client conn

testPipeline :: NatsConnection -> IO ()
testPipeline conn = do
    let source = appSource $ appData conn
    source =$= conduitParserEither message $$ printOutput2

printOutput :: Sink ByteString IO ()
printOutput = do
    r <- await
    case r of
        Just s -> do
            liftIO (print s)
            printOutput
        Nothing -> liftIO (print "Done!")

printOutput2 :: Sink (Either ParseError (PositionRange, Message)) IO ()
printOutput2 = do
    r <- await
    case r of
        Just eMsg ->
            case eMsg of
                Right (_, m) -> do
                    liftIO (print m)
                    printOutput2
                Left _ -> do
                    liftIO (print "Got parse error!")
                    printOutput2
        Nothing -> liftIO (print "Done!")
-}


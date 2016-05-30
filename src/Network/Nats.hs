{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TupleSections     #-}
module Network.Nats
    ( NatsConnection
    , NatsException (..)
    , NatsSettings (..)
    , NatsApp
    , NatsURI
    , defaultSettings
    , runNatsClient

    -- For debugging purposes the parser/writer is exported.
    , Message (..)
    , ProtocolError (..)
    , parseMessage
    , writeMessage
    ) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.STM ( atomically
                              , newTQueueIO
                              , readTQueue
                              , writeTQueue
                              )
import Control.Exception (throw)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString (ByteString)
import Data.Conduit ( Conduit
                    , Sink
                    , Source
                    , (=$=), ($$)
                    , awaitForever
                    , yield
                    )
import Data.Conduit.Attoparsec ( ParseError
                               , PositionRange
                               , conduitParserEither
                               )
import Data.Conduit.Network ( appSink
                            , appSource
                            , clientSettings
                            , runTCPClient
                            )

import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy as LBS

import Network.Nats.Message ( Message (..)
                            , ProtocolError (..)
                            , isFatalError
                            )
import Network.Nats.Parser (parseMessage)
import Network.Nats.Types ( NatsApp
                          , NatsURI
                          , NatsConnection (..)
                          , NatsException (..)
                          , NatsSettings (..)
                          , defaultSettings
                          )
import Network.Nats.Writer (writeMessage)

-- | Run the Nats client given the settings and connection URI. Once
-- the NatsApp has terminated its execution the connection is closed.
runNatsClient :: NatsSettings -> NatsURI -> NatsApp a -> IO a
runNatsClient settings' _uri app = do
    let tcpSettings = clientSettings 4222 "localhost"
    runTCPClient tcpSettings $ \appData' -> do
        txQueue' <- newTQueueIO
        let conn = NatsConnection
                     { appData  = appData'
                     , settings = settings'
                     , txQueue  = txQueue'
                     }

        -- Start the pipelines in their own threads. The pipelines
        -- and the threads will terminate when the TCP client closes down.
        mapM_ forkIO [ transmissionPipeline conn
                     , receptionPipeline conn
                     ]

        -- Execute the NatsApp in the caller's thread.
        app conn

-- | Serialize and enqueue a message for sending. The serialization is
-- performed by the calling thread.
enqueueMessage :: NatsConnection -> Message -> IO ()
enqueueMessage NatsConnection {..} msg = do
    let chunks = LBS.toChunks $ writeMessage msg
    atomically $ mapM_ (writeTQueue txQueue) chunks

transmissionPipeline :: NatsConnection -> IO ()
transmissionPipeline NatsConnection {..} = do
    let sink = appSink appData
    chunkSource =$= streamLogger $$ sink
    where
      chunkSource :: Source IO ByteString
      chunkSource = do
          chunk <- liftIO $ atomically (readTQueue txQueue)
          yield chunk
          chunkSource

-- | The reception pipeline. A stream of data from the source (produce
-- ByteStrings from the socket), to the parser (produce messages) and
-- finally to the messageSink and the message handler.
receptionPipeline :: NatsConnection -> IO ()
receptionPipeline conn = do
    let source = appSource $ appData conn
    source =$= streamLogger =$= conduitParserEither parseMessage 
        $$ messageSink
    where
      messageSink :: Sink (Either ParseError (PositionRange, Message)) IO ()
      messageSink = awaitForever $ \eMsg ->
        case eMsg of
            Right (_, msg) -> liftIO $ handleMessage conn msg
            Left err       -> liftIO $ print err
            
-- | Handle the semantic actions for one received message.
handleMessage :: NatsConnection -> Message -> IO ()

-- | Handle an Info message. Just produce and enqueue a Connect message.
handleMessage conn@NatsConnection {..} msg@Info {..} =
    enqueueMessage conn $ mkConnectMessage settings msg

-- | Handle an Err message. If the error is fatal a NatsException is thrown.
handleMessage _ (Err pe)
    | isFatalError pe = throw (NatsException pe)
    | otherwise       = return ()

handleMessage _conn _msg = putStrLn "Got something else."

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

streamLogger :: Conduit ByteString IO ByteString
streamLogger = 
    awaitForever $ \str -> do
        liftIO $ BS.putStrLn str
        yield str


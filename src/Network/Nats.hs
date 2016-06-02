{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TupleSections     #-}
module Network.Nats
    ( NatsConnection
    , NatsException (..)
    , NatsSettings (..)
    , NatsApp
    , NatsURI
    , NatsSubscriber
    , SubscriptionId (..)
    , defaultSettings
    , subscribeAsync
    , publish
    , runNatsClient

    -- For debugging purposes the parser/writer is exported.
    , Message (..)
    , ProtocolError (..)
    , parseMessage
    , writeMessage
    ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.Async (Async, async, cancel, waitCatch)
import Control.Concurrent.STM ( atomically
                              , modifyTVar
                              , newTQueueIO
                              , newTVarIO
                              , readTQueue
                              , readTVarIO
                              , writeTQueue
                              )
import Control.Exception (bracket, throw)
import Control.Monad (forever)
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
import Data.Conduit.Network ( AppData
                            , appSink
                            , appSource
                            , clientSettings
                            , runTCPClient
                            )

import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Lazy as Map

import Network.Nats.Message (Message (..))
import Network.Nats.Parser (parseMessage)
import Network.Nats.Types ( NatsApp
                          , NatsURI
                          , NatsSubscriber
                          , Subscription (..)
                          , NatsConnection (..)
                          , NatsException (..)
                          , NatsSettings (..)
                          , ProtocolError (..)
                          , SubscriptionId (..)
                          , defaultSettings
                          , isFatalError
                          , newSubscriptionId
                          , emptySubscriptionMap
                          )
import Network.Nats.Writer (writeMessage)

subscribeAsync :: NatsConnection -> ByteString -> NatsSubscriber
               -> IO SubscriptionId
subscribeAsync conn@NatsConnection {..} topic subscriber = do
    sid <- newSubscriptionId
    atomically (modifyTVar subscribers $ 
        Map.insert sid (AsyncSubscription subscriber))
    enqueueMessage conn $ Sub topic Nothing sid
    return sid

publish :: NatsConnection -> ByteString -> ByteString -> IO ()
publish conn topic payload =
    enqueueMessage conn $ Pub topic Nothing payload

-- | Run the Nats client given the settings and connection URI. Once
-- the NatsApp has terminated its execution the connection is closed.
runNatsClient :: NatsSettings -> NatsURI -> NatsApp a -> IO a
runNatsClient settings' _uri app = do
    let tcpSettings = clientSettings 4222 "localhost"
    runTCPClient tcpSettings $ \appData' ->
        bracket (setup appData')
                teardown
                (app . fst)
    where
      setup :: AppData -> IO (NatsConnection, [ Async () ])
      setup appData' = do
          txQueue'     <- newTQueueIO
          subscribers' <- newTVarIO emptySubscriptionMap
          let conn = NatsConnection
                       { appData     = appData'
                       , settings    = settings'
                       , txQueue     = txQueue'
                       , subscribers = subscribers'
                       }
          (conn,) <$> mapM async [ transmissionPipeline conn
                                 , receptionPipeline conn
                                 ]

      teardown :: (NatsConnection, [ Async () ]) -> IO ()
      teardown (_, xs) = do
          mapM_ cancel xs
          mapM_ waitCatch xs

-- | Serialize and enqueue a message for sending. The serialization is
-- performed by the calling thread.
enqueueMessage :: NatsConnection -> Message -> IO ()
enqueueMessage NatsConnection {..} msg = do
    let chunks = LBS.toChunks $ writeMessage msg
    atomically $ mapM_ (writeTQueue txQueue) chunks

transmissionPipeline :: NatsConnection -> IO ()
transmissionPipeline NatsConnection {..} = do
    let netSink = appSink appData
    stmSource =$= streamLogger $$ netSink
    where
      stmSource :: Source IO ByteString
      stmSource = 
          forever $ (liftIO $ atomically (readTQueue txQueue)) >>= yield

-- | The reception pipeline. A stream of data from the source (produce
-- ByteStrings from the socket), to the parser (produce messages) and
-- finally to the messageSink and the message handler.
receptionPipeline :: NatsConnection -> IO ()
receptionPipeline conn = do
    let netSource = appSource $ appData conn
    netSource =$= streamLogger =$= conduitParserEither parseMessage 
        $$ messageSink
    where
      messageSink :: Sink (Either ParseError (PositionRange, Message)) IO ()
      messageSink = awaitForever $ \eMsg ->
        case eMsg of
            Right (_, msg) -> liftIO $ handleMessage conn msg
            Left err       -> liftIO $ print err
            
-- | Handle the semantic actions for one received message.
handleMessage :: NatsConnection -> Message -> IO ()

-- | Handle a Msg message. Dispatch the message to the subscriber.
handleMessage NatsConnection {..} (Msg topic sid reply payload) = do
    subscribers' <- readTVarIO subscribers
    maybe (return ()) (\(AsyncSubscription subscr) ->
        forkIO (subscr (topic, sid, reply, payload)) >> return ())
        (Map.lookup sid subscribers')

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

streamLogger :: Conduit ByteString IO ByteString
streamLogger = 
    awaitForever $ \str -> do
        liftIO $ BS.putStrLn str
        yield str


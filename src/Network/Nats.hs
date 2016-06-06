{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TupleSections     #-}
module Network.Nats
    ( Connection
    , Settings (..)
    , LoggerSpec (..)
    , NatsMsg (..)
    , JsonMsg (..)
    , NatsException (..)
    , NatsURI
    , Topic
    , Payload
    , QueueGroup
    , SubscriptionId (..)
    , defaultSettings
    , subAsync
    , subAsync'
    , subAsyncJson
    , subAsyncJson'
    , subQueue
    , subQueue'
    , unsub
    , nextMsg
    , nextJsonMsg
    , pub
    , pub'
    , pubJson
    , pubJson'
    , runNatsClient

    -- For debugging purposes the parser/writer is exported.
    , Message (..)
    , ProtocolError (..)
    , parseMessage
    , writeMessage
    ) where

import Control.Concurrent ( forkIO
                          , newEmptyMVar
                          , putMVar
                          , takeMVar
                          )
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
import Control.Monad (forever, void)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (FromJSON, ToJSON, decode', encode)
import Data.Conduit ( Sink
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
import qualified Data.ByteString.Lazy.Char8 as LBS

import Network.Nats.Connection ( Connection (..)
                               , Settings (..)
                               , defaultSettings
                               )
import Network.Nats.Logger (LoggerSpec (..), mkLoggers)
import Network.Nats.Message (Message (..))
import Network.Nats.Parser (parseMessage)
import Network.Nats.Types ( Topic 
                          , Payload
                          , QueueGroup
                          , NatsURI
                          , NatsException (..)
                          , ProtocolError (..)
                          , isFatalError
                          )
import Network.Nats.Subscriber ( NatsMsg (..)
                               , JsonMsg (..)
                               , MsgQueue (..)
                               , Subscriber (..)
                               , SubscriptionId (..)
                               , empty
                               , addSubscriber
                               , deleteSubscriber
                               , lookupSubscriber
                               , newSubscriptionId
                               )
import Network.Nats.Writer (writeMessage)

-- | Subscribe on a Topic with an asyncronous action to handle
-- messages sent to this Topic. The asyncronous action will be
-- executed in a new thread.
subAsync :: Connection -> Topic -> Maybe QueueGroup 
         -> (NatsMsg -> IO ()) -> IO SubscriptionId
subAsync conn@Connection {..} topic queueGroup action = do
    sid <- newSubscriptionId
    atomically (modifyTVar subscribers $ 
        addSubscriber sid (AsyncSubscriber action))
    enqueueMessage conn $ Sub topic queueGroup sid
    return sid

-- | Subscribe on a Topic with an asyncronous action to handle
-- messages sent to this Topic. The asyncronous action will be
-- executed in a new thread. Shortcut without QueueGroup.
subAsync' :: Connection -> Topic -> (NatsMsg -> IO ())
          -> IO SubscriptionId
subAsync' conn topic = subAsync conn topic Nothing

-- | Subscribe on a Topic with an asyncronous action to handle
-- JSON messages sent to this Topic. The asyncronous action will be
-- executed in a new thread.
subAsyncJson :: FromJSON a => Connection -> Topic -> Maybe QueueGroup
             -> (JsonMsg a -> IO ()) -> IO SubscriptionId
subAsyncJson conn topic queueGroup action =
    subAsync conn topic queueGroup $ \(NatsMsg topic' sid reply payload) ->
        action $ JsonMsg topic' sid reply (decode' payload)

-- | Subscribe on a Topic with an asyncronous action to handle
-- JSON messages sent to this Topic. The asyncronous action will be
-- executed in a new thread. Shortcut without QueueGroup.
subAsyncJson' :: FromJSON a => Connection -> Topic
              -> (JsonMsg a -> IO ()) -> IO SubscriptionId
subAsyncJson' conn topic = subAsyncJson conn topic Nothing

-- | Subscribe to a Topic where the messages are put to a MsgQueue.
subQueue :: Connection -> Topic -> Maybe QueueGroup
         -> IO (SubscriptionId, MsgQueue)
subQueue conn@Connection {..} topic queueGroup = do
    sid   <- newSubscriptionId
    queue <- newTQueueIO
    atomically (modifyTVar subscribers $
        addSubscriber sid (QueueSubscriber queue))
    enqueueMessage conn $ Sub topic queueGroup sid
    return $ (sid, MsgQueue queue)

-- | Subscribe to a Topic where the messages are put to a MsgQueue.
-- Shortcut wihtout QueueGroup.
subQueue' :: Connection -> Topic -> IO (SubscriptionId, MsgQueue)
subQueue' conn topic = subQueue conn topic Nothing

-- | Unsubscribe from a Topic using the SubscriptionId from when
-- subscribing.
unsub :: Connection -> SubscriptionId -> IO ()
unsub conn@Connection {..} sid = do
    enqueueMessage conn $ Unsub sid Nothing
    atomically (modifyTVar subscribers $ deleteSubscriber sid) 

-- | Read the next message from the MsgQueue. The call is blocking
-- until a message arrives or interrupted by System.Timeout.timeout.
nextMsg :: MsgQueue -> IO NatsMsg
nextMsg (MsgQueue queue) = atomically $ readTQueue queue

-- | Read the next JSON message from the MsgQueue. The call is blocking
-- until a message arrives or interrupted by System.Timeout.timeout.
nextJsonMsg :: FromJSON a => MsgQueue -> IO (JsonMsg a)
nextJsonMsg queue = do
    NatsMsg topic sid reply payload <- nextMsg queue
    return $ JsonMsg topic sid reply (decode' payload)

-- | Publish a message to a Topic.
pub :: Connection -> Topic -> Maybe Topic -> Payload -> IO ()
pub conn topic reply payload = 
    enqueueMessage conn $ Pub topic reply payload

-- | Publish a message to a Topic. Shortcut with no reply-to Topic.
pub' :: Connection -> Topic -> Payload -> IO ()
pub' conn topic = pub conn topic Nothing

-- | Publish a JSON message to a Topic.
pubJson :: ToJSON a => Connection -> Topic -> Maybe Topic -> a -> IO ()
pubJson conn topic reply = pub conn topic reply . encode

-- | Publish a JSON message to a Topic. Shortcut with no reply-to Topic.
pubJson' :: ToJSON a => Connection -> Topic -> a -> IO ()
pubJson' conn topic = pubJson conn topic Nothing

-- | Run the Nats client given the settings and connection URI. Once
-- the NatsApp has terminated its execution the connection is closed.
runNatsClient :: Settings -> NatsURI -> (Connection -> IO a) -> IO a
runNatsClient settings'@Settings {..} _uri app = do
    let tcpSettings = clientSettings 4222 "localhost"
    runTCPClient tcpSettings $ \appData' ->
        bracket (setup appData') teardown $ \(conn, _) -> do
            -- Now we must wait for the Connect message to have been
            -- added to the txQueue before letting the app
            -- starting the execution.
            takeMVar $ startUpSync conn
            app conn
    where
      setup :: AppData -> IO (Connection, [ Async () ])
      setup appData' = do
          startUpSync'         <- newEmptyMVar
          txQueue'             <- newTQueueIO
          subscribers'         <- newTVarIO empty
          (inp, outp, cleanUp) <- mkLoggers loggerSpec
          let conn = Connection
                       { appData     = appData'
                       , startUpSync = startUpSync'
                       , settings    = settings'
                       , txQueue     = txQueue'
                       , subscribers = subscribers'
                       , inpLogger   = inp
                       , outpLogger  = outp
                       , logCleanUp  = cleanUp
                       }
          (conn,) <$> mapM async [ transmissionPipeline conn
                                 , receptionPipeline conn
                                 ]

      teardown :: (Connection, [ Async () ]) -> IO ()
      teardown (conn, xs) = do
          mapM_ cancel xs
          mapM_ waitCatch xs
          logCleanUp conn

-- | Serialize and enqueue a message for sending. The serialization is
-- performed by the calling thread.
enqueueMessage :: Connection -> Message -> IO ()
enqueueMessage Connection {..} msg = do
    outpLogger msg
    let chunks = LBS.toChunks $ writeMessage msg
    atomically $ mapM_ (writeTQueue txQueue) chunks

transmissionPipeline :: Connection -> IO ()
transmissionPipeline Connection {..} = do
    let netSink = appSink appData
    stmSource $$ netSink
    where
      stmSource :: Source IO BS.ByteString
      stmSource = 
          forever $ (liftIO $ atomically (readTQueue txQueue)) >>= yield

-- | The reception pipeline. A stream of data from the source (produce
-- ByteStrings from the socket), to the parser (produce messages) and
-- finally to the messageSink and the message handler.
receptionPipeline :: Connection -> IO ()
receptionPipeline conn = do
    let netSource = appSource $ appData conn
    netSource =$= conduitParserEither parseMessage $$ messageSink
    where
      messageSink :: Sink (Either ParseError (PositionRange, Message)) IO ()
      messageSink = awaitForever $ \eMsg ->
        case eMsg of
            Right (_, msg) -> liftIO $ handleMessage conn msg
            Left err       -> liftIO $ print err
            
-- | Handle the semantic actions for one received message.
handleMessage :: Connection -> Message -> IO ()
handleMessage conn@Connection {..} msg = do
    inpLogger msg
    handleMessage' conn msg

handleMessage' :: Connection -> Message -> IO ()

-- | Handle a Msg message. Dispatch the message to the subscriber. If
-- there'e no subscriber the message is dropped.
handleMessage' Connection {..} (Msg topic sid reply payload) = do
    subscribers' <- readTVarIO subscribers
    maybe (return ()) 
          (deliverSubscription $ NatsMsg topic sid reply payload)
          (lookupSubscriber sid subscribers')

-- | Handle an Info message. Just produce and enqueue a Connect message.
handleMessage' conn@Connection {..} msg@Info {..} = do
    enqueueMessage conn $ mkConnectMessage settings msg

    -- Now when the Connect message has been put on the queue, the
    -- rest of the application can be unlocked.
    putMVar startUpSync ()

-- | Handle a Ping message. Just reply with a Pong message.
handleMessage' conn Ping = enqueueMessage conn Pong

-- | Handle an Err message. If the error is fatal a NatsException is thrown.
handleMessage' _ (Err pe)
    | isFatalError pe = throw (NatsException pe)
    | otherwise       = return ()

handleMessage' _conn _msg = return ()

-- | Deliver a message to a subscriber.
deliverSubscription :: NatsMsg -> Subscriber -> IO ()
deliverSubscription msg (AsyncSubscriber action) =
    void $ forkIO (action msg)

deliverSubscription msg (QueueSubscriber queue) =
    atomically $ writeTQueue queue msg

-- | Given the settings and the Info record, produce a Connect record.
mkConnectMessage :: Settings -> Message -> Message
mkConnectMessage Settings {..} Info {..} =
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

{-streamLogger :: Conduit BS.ByteString IO BS.ByteString
streamLogger = 
    awaitForever $ \str -> do
        liftIO $ BS.putStrLn str
        yield str
-}


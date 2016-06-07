{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
module Network.NatsTests
    ( asyncSubscribeSingleMsg
    , asyncSubscribeSingleJsonMsg
    , syncSubscribeSingleMsg
    , syncSubscribeSingleJsonMsg
    , syncSubscribeSeveralMsgWithTmo
    , syncSubscribeSeveralJsonMsgWithTmo
    , unsubscribe
    , requestOneItem
    ) where

import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, takeMVar)
import Control.Monad (void)
import Data.Aeson (FromJSON, ToJSON)
import Data.ByteString.Lazy.Char8 (ByteString)
import GHC.Generics (Generic)
import System.Timeout (timeout)
import Test.HUnit

import qualified Data.ByteString as BS

import Network.Nats

data TestMsg = TestMsg
    { stringField :: !String
    , intField    :: !Int
    } deriving (Generic, Eq, Show)

instance FromJSON TestMsg
instance ToJSON TestMsg

asyncSubscribeSingleMsg :: Assertion
asyncSubscribeSingleMsg =
    void $ runNatsClient settings defaultURI $ \conn -> do
        sync <- newEmptyMVar
        sid <- subAsync' conn "foo" $ handler sync
        pub' conn "foo" "Hello World!"

        (sid', value) <- takeMVar sync
        assertEqual "Shall be equal" sid sid'
        assertEqual "Shall be equal" "Hello World!" value
    where
      handler :: MVar (SubscriptionId, ByteString) -> NatsMsg -> IO ()
      handler sync (NatsMsg _ sid _ payload) = putMVar sync (sid, payload)

asyncSubscribeSingleJsonMsg :: Assertion
asyncSubscribeSingleJsonMsg =
    void $ runNatsClient settings defaultURI $ \conn -> do
        sync <- newEmptyMVar
        sid <- subAsyncJson' conn "foo" $ handler sync
        let msg = TestMsg { stringField = "foo", intField = 123 }
        pubJson' conn "foo" msg

        (sid', value) <- takeMVar sync
        assertEqual "Shall be equal" sid sid'
        assertEqual "Shall be equal" (Just msg) value
    where
      handler :: MVar (SubscriptionId, Maybe TestMsg) -> JsonMsg TestMsg
              -> IO ()
      handler sync (JsonMsg _ sid _ payload) = putMVar sync (sid, payload)

syncSubscribeSingleMsg :: Assertion
syncSubscribeSingleMsg =
    void $ runNatsClient settings defaultURI $ \conn -> do
        (sid, queue) <- subQueue' conn "foo"
        pub' conn "foo" "Hello sync world!"

        NatsMsg _ sid' _ payload <- nextMsg queue
        assertEqual "Shall be equal" sid sid'
        assertEqual "Shall be equal" "Hello sync world!" payload

syncSubscribeSingleJsonMsg :: Assertion
syncSubscribeSingleJsonMsg =
    void $ runNatsClient settings defaultURI $ \conn -> do
        (sid, queue) <- subQueue' conn "foo"
        let msg = TestMsg { stringField = "foo", intField = 234 }
        pubJson' conn "foo" msg

        JsonMsg _ sid' _ payload <- nextJsonMsg queue
        assertEqual "Shall be equal" sid sid'
        assertEqual "Shall be equal" (Just msg) payload

syncSubscribeSeveralMsgWithTmo :: Assertion
syncSubscribeSeveralMsgWithTmo =
    void $ runNatsClient settings defaultURI $ \conn -> do
        (_, queue) <- subQueue' conn "foo"
        pub' conn "foo" "one"
        pub' conn "foo" "two"
        pub' conn "foo" "three"

        Just (NatsMsg _ _ _ payload1) <- timeout 100000 $ nextMsg queue
        Just (NatsMsg _ _ _ payload2) <- timeout 100000 $ nextMsg queue
        Just (NatsMsg _ _ _ payload3) <- timeout 100000 $ nextMsg queue

        assertEqual "Shall be equal" "one" payload1
        assertEqual "Shall be equal" "two" payload2
        assertEqual "Shall be equal" "three" payload3

        result <- timeout 100000 $ nextMsg queue
        assertEqual "Shall be equal" Nothing result

syncSubscribeSeveralJsonMsgWithTmo :: Assertion
syncSubscribeSeveralJsonMsgWithTmo =
    void $ runNatsClient settings defaultURI $ \conn -> do
        (_, queue) <- subQueue' conn "foo"
        let msg1 = TestMsg { stringField = "foo", intField = 345 }
            msg2 = TestMsg { stringField = "foo", intField = 456 }
            msg3 = TestMsg { stringField = "foo", intField = 567 }

        pubJson' conn "foo" msg1
        pubJson' conn "foo" msg2
        pubJson' conn "foo" msg3

        Just (JsonMsg _ _ _ payload1) <- timeout 100000 $ nextJsonMsg queue
        Just (JsonMsg _ _ _ payload2) <- timeout 100000 $ nextJsonMsg queue
        Just (JsonMsg _ _ _ payload3) <- timeout 100000 $ nextJsonMsg queue

        assertEqual "Shall be equal" (Just msg1) payload1
        assertEqual "Shall be equal" (Just msg2) payload2
        assertEqual "Shall be equal" (Just msg3) payload3

        result <- timeout 100000 $ nextJsonMsg queue
        assertEqual "Shall be equal" Nothing
                    (result :: Maybe (JsonMsg TestMsg))

unsubscribe :: Assertion
unsubscribe =
    void $ runNatsClient settings defaultURI $ \conn -> do
        (sid, queue) <- subQueue' conn "foo"

        pub' conn "foo" "one"
        Just (NatsMsg _ _ _ payload) <- timeout 100000 $ nextMsg queue

        unsub conn sid
        pub' conn "foo" "two"
        result <- timeout 100000 $ nextMsg queue

        assertEqual "Shall be equal" "one" payload
        assertEqual "Shall be equal" Nothing result

requestOneItem :: Assertion
requestOneItem =
    void $ runNatsClient settings defaultURI $ \conn -> do
        void $ subAsync' conn "help" $ \(NatsMsg _ _ mReply _) -> do
            case mReply of
                Just reply -> pub' conn reply "pong"
                Nothing    -> return ()

        Just (NatsMsg _ _ _ payload) <-
            request conn "help" "ping" Infinity

        assertEqual "Shall be equal" "pong" payload

settings :: Settings
settings = defaultSettings { verbose    = False
                           , pedantic   = True
                           , loggerSpec = StdoutLogger
                           }

defaultURI :: BS.ByteString
defaultURI = "nats://localhost:4222"

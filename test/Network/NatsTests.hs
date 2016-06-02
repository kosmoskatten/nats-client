{-# LANGUAGE OverloadedStrings #-}
module Network.NatsTests
    ( asyncSubscribeSingleMsg
    , syncSubscribeSingleMsg
    , syncSubscribeSeveralMsgWithTmo
    ) where

import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, takeMVar)
import Control.Monad (void)
import Data.ByteString.Char8 (ByteString)
import System.Timeout (timeout)
import Test.HUnit

import Network.Nats

asyncSubscribeSingleMsg :: Assertion
asyncSubscribeSingleMsg =
    void $ runNatsClient natsSettings "" $ \conn -> do
        sync <- newEmptyMVar
        sid <- subscribeAsync conn "foo" $ handler sync
        publish conn "foo" "Hello World!"

        (sid', value) <- takeMVar sync
        assertEqual "Shall be equal" sid sid'
        assertEqual "Shall be equal" "Hello World!" value
    where
      handler :: MVar (SubscriptionId, ByteString) -> NatsSubscriber
      handler sync (_, sid, _, payload) = putMVar sync (sid, payload)

syncSubscribeSingleMsg :: Assertion
syncSubscribeSingleMsg =
    void $ runNatsClient natsSettings "" $ \conn -> do
        queue <- subscribeSync conn "foo"
        publish conn "foo" "Hello sync world!"

        (_, _, _, value) <- nextMsg queue
        assertEqual "Shall be equal" "Hello sync world!" value

syncSubscribeSeveralMsgWithTmo :: Assertion
syncSubscribeSeveralMsgWithTmo =
    void $ runNatsClient natsSettings "" $ \conn -> do
        queue <- subscribeSync conn "foo"
        publish conn "foo" "one"
        publish conn "foo" "two"
        publish conn "foo" "three"

        Just (_, _, _, value1) <- timeout 100000 $ nextMsg queue
        Just (_, _, _, value2) <- timeout 100000 $ nextMsg queue
        Just (_, _, _, value3) <- timeout 100000 $ nextMsg queue

        assertEqual "Shall be equal" "one" value1
        assertEqual "Shall be equal" "two" value2
        assertEqual "Shall be equal" "three" value3

        result <- timeout 100000 $ nextMsg queue
        assertEqual "Shall be equal" Nothing result

natsSettings :: NatsSettings
natsSettings = defaultSettings { verbose  = True
                               , pedantic = True
                               }

{-# LANGUAGE OverloadedStrings #-}
module Network.NatsTests
    ( asyncSubscribeSingleMsg
    , syncSubscribeSingleMsg
    , syncSubscribeSeveralMsgWithTmo
    ) where

import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, takeMVar)
import Control.Monad (void)
import Data.ByteString.Lazy.Char8 (ByteString)
import System.Timeout (timeout)
import Test.HUnit

import Network.Nats

asyncSubscribeSingleMsg :: Assertion
asyncSubscribeSingleMsg =
    void $ runNatsClient settings "" $ \conn -> do
        sync <- newEmptyMVar
        sid <- subAsync conn "foo" $ handler sync
        pub conn "foo" "Hello World!"

        (sid', value) <- takeMVar sync
        assertEqual "Shall be equal" sid sid'
        assertEqual "Shall be equal" "Hello World!" value
    where
      handler :: MVar (SubscriptionId, ByteString) -> NatsMsg -> IO ()
      handler sync (NatsMsg _ sid _ payload) = putMVar sync (sid, payload)

syncSubscribeSingleMsg :: Assertion
syncSubscribeSingleMsg =
    void $ runNatsClient settings "" $ \conn -> do
        queue <- subQueue conn "foo"
        pub conn "foo" "Hello sync world!"

        NatsMsg _ _ _ payload <- nextMsg queue
        assertEqual "Shall be equal" "Hello sync world!" payload

syncSubscribeSeveralMsgWithTmo :: Assertion
syncSubscribeSeveralMsgWithTmo =
    void $ runNatsClient settings "" $ \conn -> do
        queue <- subQueue conn "foo"
        pub conn "foo" "one"
        pub conn "foo" "two"
        pub conn "foo" "three"

        Just (NatsMsg _ _ _ payload1) <- timeout 100000 $ nextMsg queue
        Just (NatsMsg _ _ _ payload2) <- timeout 100000 $ nextMsg queue
        Just (NatsMsg _ _ _ payload3) <- timeout 100000 $ nextMsg queue

        assertEqual "Shall be equal" "one" payload1
        assertEqual "Shall be equal" "two" payload2
        assertEqual "Shall be equal" "three" payload3

        result <- timeout 100000 $ nextMsg queue
        assertEqual "Shall be equal" Nothing result

settings :: Settings
settings = defaultSettings { verbose  = True
                           , pedantic = True
                           }

{-# LANGUAGE OverloadedStrings #-}
module Network.NatsTests
    ( asyncSubscribeSingleMsg
    ) where

import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, takeMVar)
import Control.Monad (void)
import Data.ByteString.Char8 (ByteString)
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

natsSettings :: NatsSettings
natsSettings = defaultSettings { verbose  = True
                               , pedantic = True
}

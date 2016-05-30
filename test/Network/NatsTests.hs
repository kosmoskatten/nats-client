{-# LANGUAGE OverloadedStrings #-}
module Network.NatsTests
    ( connectToServer
    ) where

import Control.Concurrent (threadDelay)
import Test.HUnit

import Network.Nats

-- | Assume a running NATS server.
connectToServer :: Assertion
connectToServer = do
    result <- runNatsClient natsSettings "" delayApp
    assertBool "Shall give True" result

natsSettings :: NatsSettings
natsSettings = defaultSettings { verbose  = True
                               , pedantic = True
}

delayApp :: NatsConnection -> IO Bool
delayApp _ = do
    threadDelay 500000
    return True

{-# LANGUAGE OverloadedStrings #-}
module Network.Nats
    ( NatsConnection
    , runNatsClient
    , readSingleOutput
    ) where

import Data.ByteString (ByteString)
import Data.Conduit
import Data.Conduit.Network
--import Data.Streaming.Network (AppData)

data NatsConnection = NatsConnection
    { appData :: !AppData
    }

runNatsClient :: ByteString -> (NatsConnection -> IO a) -> IO a
runNatsClient _ client = do
    let settings = clientSettings 4222 "localhost"
    runTCPClient settings $ \appData' -> do
        let conn = NatsConnection { appData = appData' }
        client conn

readSingleOutput :: NatsConnection -> IO ByteString
readSingleOutput conn = do
    let source = appSource $ appData conn
    source $$ do r <- await
                 case r of
                    Just s -> return s
                    Nothing -> return ""


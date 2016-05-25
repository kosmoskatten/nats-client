{-# LANGUAGE OverloadedStrings #-}
module Network.Nats
    ( NatsConnection
    , runNatsClient
    , testPipeline
    ) where

import Control.Monad.IO.Class
import Data.ByteString (ByteString)
import Data.Conduit
import Data.Conduit.Attoparsec
import Data.Conduit.Network

import Network.Nats.Message
import Network.Nats.Parser

data NatsConnection = NatsConnection
    { appData :: !AppData
    }

runNatsClient :: ByteString -> (NatsConnection -> IO a) -> IO a
runNatsClient _ client = do
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


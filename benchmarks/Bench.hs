{-# LANGUAGE OverloadedStrings #-}
module Main
    ( main
    ) where

import Control.Monad (replicateM_, void)
import Control.Concurrent.STM ( STM
                              , TVar
                              , atomically
                              , modifyTVar
                              , newTVarIO
                              , readTVar
                              , retry
                              )
import Criterion.Main ( Benchmark
                      , defaultMain
                      , bgroup
                      , bench
                      , env
                      , nf
                      , whnfIO
                      )
import Data.Attoparsec.ByteString.Char8 ( IResult (..)
                                        , Result
                                        , parse
                                        )
import Data.ByteString.Lazy.Builder ( lazyByteString
                                    , toLazyByteString
                                    )

import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy.Char8 as LBS

import Network.Nats

main :: IO ()
main = defaultMain suite

suite :: [Benchmark]
suite =
    [ bgroup "pub-writer"
        [ env smallPubMessages $ \xs ->
            bench "million * 48 bytes" $ nf writePubs xs

        , env mediumPubMessages $ \xs ->
            bench "million * 480 bytes" $ nf writePubs xs

        , env largePubMessages $ \xs ->
            bench "million * 4800 bytes" $ nf writePubs xs
        ]
    , bgroup "msg-parser"
        [ env smallMsgMessages $ \xs ->
            bench "million * 48 bytes" $ nf parseMsgs xs

        , env mediumMsgMessages $ \xs ->
            bench "million * 480 bytes" $ nf parseMsgs xs

        , env largeMsgMessages $ \xs ->
            bench "million * 4800 bytes" $ nf parseMsgs xs
        ]
    , bgroup "pubsub-nats"
        [ bench "100000 pub" $ whnfIO (pubPerf 100000)
        , bench "10000 pubsub" $ whnfIO (pubSubPerf 10000)
        ]
    ]

-- | Write a list of Pub messages to a list of lazy ByteStrings.
writePubs :: [Message] -> [LBS.ByteString]
writePubs = map writeMessage

-- | Parse a list of ByteStrings to a list of Msg messages.
parseMsgs :: [BS.ByteString] -> [Message]
parseMsgs = map (fromResult . parse parseMessage)
    where
      fromResult :: Result Message -> Message
      fromResult (Done _ msg)   = msg
      fromResult (Partial cont) = fromResult (cont "")
      fromResult _              = error "Shall not happen"

-- | Send the given number of Pub messages containing the payload "hello".
-- The benchmark requires a running NATS server.
pubPerf :: Int -> IO ()
pubPerf rep =
    runNatsClient defaultSettings defaultURI $ \conn ->
        replicateM_ rep $ pub' conn "bench" "hello"

-- | Send the given number of Pub messages containing the payload "hello"
-- Subscribe to and receive the same number of messages.
-- The benchmark requires a running NATS server.
pubSubPerf :: Int -> IO ()
pubSubPerf rep =
    runNatsClient defaultSettings defaultURI $ \conn -> do
        tvar <- newTVarIO 0
        void $ subAsync' conn "bench" $ receiver tvar
        replicateM_ rep $ pub' conn "bench" "hello"

        atomically $ waitForValue tvar rep

receiver :: TVar Int -> NatsMsg -> IO ()
receiver tvar _ = atomically $ modifyTVar tvar (+ 1)

waitForValue :: TVar Int -> Int -> STM ()
waitForValue tvar value = do
    value' <- readTVar tvar
    if value' /= value
        then retry
        else return ()

million :: Int
million = 1000000

small :: Int
small = 1

medium :: Int
medium = 10

large :: Int
large = 100

smallPubMessages :: IO [Message]
smallPubMessages = million `pubMessages` small

mediumPubMessages :: IO [Message]
mediumPubMessages = million `pubMessages` medium

largePubMessages :: IO [Message]
largePubMessages = million `pubMessages` large

smallMsgMessages :: IO [BS.ByteString]
smallMsgMessages = million `msgMessages` small

mediumMsgMessages :: IO [BS.ByteString]
mediumMsgMessages = million `msgMessages` medium

largeMsgMessages :: IO [BS.ByteString]
largeMsgMessages = million `msgMessages` large

pubMessages :: Int -> Int -> IO [Message]
pubMessages rep size = return $ replicate rep (pubMessage size)

msgMessages :: Int -> Int -> IO [BS.ByteString]
msgMessages rep size = do
    let xs = replicate rep (msgMessage size)
    return $ map (LBS.toStrict . writeMessage) xs

pubMessage :: Int -> Message
pubMessage = Pub "TOPIC.INBOX" (Just "REPLY.INBOX") . replicatePayload

msgMessage :: Int -> Message
msgMessage = 
    Msg "TOPIC.INBOX" (Sid 123456) (Just "REPLY.INBOX") . replicatePayload

replicatePayload :: Int -> LBS.ByteString
replicatePayload n =
    let p = map lazyByteString $ replicate n payloadChunk
    in toLazyByteString $ mconcat p

-- | A basic "random" payload chunk with 48 characters.
payloadChunk :: LBS.ByteString
payloadChunk = "pq01ow92ie83ue74ur74yt65jf82nc8emr8dj48v.dksme2z"

defaultURI :: BS.ByteString
defaultURI = "nats://localhost:4222"

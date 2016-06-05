{-# LANGUAGE OverloadedStrings #-}
module Main
    ( main
    ) where

import Criterion.Main ( Benchmark
                      , defaultMain
                      , bgroup
                      , bench
                      , env
                      , nf
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
    [ bgroup "Pub message writer benchmarks"
        [ env smallPubMessages $ \xs ->
            bench "Small (48 bytes) Pub msgs" $ nf writePubs xs

        , env mediumPubMessages $ \xs ->
            bench "Medium (480 bytes) Pub msgs" $ nf writePubs xs

        , env largePubMessages $ \xs ->
            bench "Large (4800 bytes) Pub msgs" $ nf writePubs xs
        ]
    , bgroup "Msg message parser benchmarks"
        [ env smallMsgMessages $ \xs ->
            bench "Small (48 bytes) Msg msgs" $ nf parseMsgs xs

        , env mediumMsgMessages $ \xs ->
            bench "Medium (480 bytes) Msg msgs" $ nf parseMsgs xs

        , env largeMsgMessages $ \xs ->
            bench "Large (4800 bytes) Msg msgs" $ nf parseMsgs xs
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

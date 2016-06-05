{-# LANGUAGE OverloadedStrings #-}
module Main
    ( main
    ) where

import Criterion.Main
import Data.ByteString.Lazy.Builder

import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy.Char8 as LBS

import Network.Nats

main :: IO ()
main = defaultMain suite

suite :: [Benchmark]
suite =
    [ bgroup "Pub message writer benchmarks"
        [ env smallPubMessages $ \xs ->
            bench "Small (48 byte) Pub msgs" $ nf writePubs xs

        , env mediumPubMessages $ \xs ->
            bench "Medium (480 byte) Pub msgs" $ nf writePubs xs

        , env largePubMessages $ \xs ->
            bench "Large (4800 byte) Pub msgs" $ nf writePubs xs
        ]
    ]

writePubs :: [Message] -> [LBS.ByteString]
writePubs = map writeMessage

smallPubMessages :: IO [Message]
smallPubMessages = return $ replicate 1000000 (pubMessage 1)

mediumPubMessages :: IO [Message]
mediumPubMessages = return $ replicate 1000000 (pubMessage 10)

largePubMessages :: IO [Message]
largePubMessages = return $ replicate 1000000 (pubMessage 100)

pubMessage :: Int -> Message
pubMessage = Pub "TOPIC.INBOX" (Just "REPLY.INBOX") . replicatePayload

replicatePayload :: Int -> LBS.ByteString
replicatePayload n =
    let p = map lazyByteString $ replicate n payloadChunk
    in toLazyByteString $ mconcat p

-- | A basic "random" payload chunk with 48 characters.
payloadChunk :: LBS.ByteString
payloadChunk = "pq01ow92ie83ue74ur74yt65jf82nc8emr8dj48v.dksme2z"

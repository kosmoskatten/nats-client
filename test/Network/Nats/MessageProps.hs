{-# LANGUAGE OverloadedStrings    #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Network.Nats.MessageProps
    ( encodeDecodeMessage
    ) where

import Data.Attoparsec.ByteString.Char8
import Data.ByteString.Char8 (ByteString)
import Data.ByteString.Builder (toLazyByteString)
import Test.QuickCheck

import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy.Char8 as LBS

import Network.Nats.Message (Message (..))
import Network.Nats.Parser (message)
import Network.Nats.Writer (writeMessage)

-- | Arbitrary instance for Message.
instance Arbitrary Message where
    arbitrary =
        Info <$> perhaps valueString
             <*> perhaps valueString
             <*> perhaps valueString
             <*> perhaps valueString
             <*> perhaps posInt
             <*> arbitrary
             <*> arbitrary
             <*> arbitrary
             <*> arbitrary
             <*> perhaps posInt

-- | Test by write a Message to ByteString, and parse it back again.
encodeDecodeMessage :: Message -> Bool
encodeDecodeMessage msg =
    let asByteString = LBS.toStrict $ toLazyByteString $ writeMessage msg
    in verify (parse message asByteString)
    where
      verify :: IResult ByteString Message -> Bool
      verify result =
        case result of
            (Done _ msg2) -> msg == msg2
            (Partial g)   -> verify (g "")
            _             -> False

-- | Generate Maybe's for the tailor made generators.
perhaps :: Gen a -> Gen (Maybe a)
perhaps gen = oneof [ return Nothing, Just <$> gen ]

-- | Generate a ByteString which not contains any quote characters.
valueString :: Gen ByteString
valueString =
    BS.pack <$> listOf (elements selection)
    where
      selection :: [Char]
      selection = ['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ "+-_!?*(){} "

-- | Generate a positive integer. Can be max size of Int.
posInt :: Gen Int
posInt = choose (0, maxBound)

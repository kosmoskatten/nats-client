module Network.Nats.Logger
    ( Logger
    , LoggerSpec (..)
    , mkLoggers
    ) where

import Data.Monoid ((<>))
import System.Log.FastLogger ( LogType (..)
                             , FastLogger
                             , defaultBufSize
                             , newFastLogger
                             , toLogStr
                             )

import Network.Nats.Message (Message (..))
import Network.Nats.Writer (writeMessage)

-- | A Logger is an IO action taking a Message.
type Logger = (Message -> IO ())

-- | Specify the kind of logging requested.
data LoggerSpec
    = NoLogger
      -- ^ Logging turned off.
    | StdoutLogger
      -- ^ Log to stdout.
    | FileLogger !FilePath
      -- ^ Log to the specified file.
    deriving Show

-- | Make the loggers. They are (input, output, clean up action).
mkLoggers :: LoggerSpec -> IO (Logger, Logger, IO ())
mkLoggers logger = do
    (fl, cleanUp) <- newFastLogger $ toLogType logger
    return (inputLogger fl, outputLogger fl, cleanUp)

toLogType :: LoggerSpec -> LogType
toLogType NoLogger          = LogNone
toLogType StdoutLogger      = LogStdout defaultBufSize
toLogType (FileLogger path) = LogFileNoRotate path defaultBufSize

inputLogger :: FastLogger -> Logger
inputLogger logger msg = do
    let inp = toLogStr ("<= " :: String) 
           <> toLogStr (writeMessage msg)
           <> toLogStr ("\r\n" :: String)
    logger inp

outputLogger :: FastLogger -> Logger
outputLogger logger msg = do
    let outp = toLogStr ("=> " :: String) 
            <> toLogStr (writeMessage msg)
            <> toLogStr ("\r\n" :: String)
    logger outp

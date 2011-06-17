{-# LANGUAGE RecordWildCards, NamedFieldPuns #-}
module Regex.Genex.Pure (genexPure) where
import Control.Monad.Logic.Class (MonadLogic(..))
import qualified Data.Text as T
import qualified Data.IntSet as IntSet
import qualified Data.Set as Set
import Data.List (intersect, (\\))
import Control.Monad
import Control.Monad.Stream
import Regex.Genex.Normalize (normalize)
import Debug.Trace
import Text.Regex.TDFA.Pattern
import Text.Regex.TDFA.ReadRegex (parseRegex)
import Control.Monad.State
import Control.Applicative

parse :: String -> Pattern
parse r = case parseRegex r of
    Right (pattern, _) -> pattern
    Left x -> error $ show x

genexPure :: [String] -> [String]
genexPure = map T.unpack . foldl1 intersect . map (toList . run . normalize IntSet.empty . parse)

maxRepeat :: Int
maxRepeat = 3

each = foldl1 (<|>) . map return

run :: Pattern -> Stream T.Text
run p = case p of
    PEmpty -> pure T.empty
    PChar{..} -> isChar getPatternChar
    PAny {getPatternSet = PatternSet (Just cset) _ _ _} -> each $ map T.singleton $ Set.toList cset
    PQuest p -> pure T.empty <|> run p
    PPlus p -> run $ PBound 1 Nothing p
    PStar _ p -> run $ PBound 0 Nothing p
    PBound low high p -> do
        n <- each [low..maybe (low+maxRepeat) id high]
        fmap T.concat . sequence $ replicate n (run p) 
    PConcat ps -> fmap T.concat . suspended . sequence $ map run ps
    POr xs -> foldl1 mplus $ map run xs
    PDot{} -> notChars []
    PEscape {..} -> case getPatternChar of
        'n' -> isChar '\n'
        't' -> isChar '\t'
        'r' -> isChar '\r'
        'f' -> isChar '\f'
        'a' -> isChar '\a'
        'e' -> isChar '\ESC'
        'd' -> chars $ ['0'..'9']
        'w' -> chars $ ['0'..'9'] ++ '_' : ['a'..'z'] ++ ['A'..'Z']
        's' -> chars "\9\10\12\13\32"
        'W' -> notChars $ ['0'..'9']
        'S' -> notChars $ ['0'..'9'] ++ '_' : ['a'..'z'] ++ ['A'..'Z']
        'D' -> notChars "\9\10\12\13\32"
        ch  -> isChar ch
    _      -> error $ show p
    where
    isChar = return . T.singleton
    chars = each . map T.singleton
    notChars = chars . ([' '..'~'] \\)

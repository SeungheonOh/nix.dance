#! /usr/bin/env nix-shell
#! nix-shell -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/914ef51ffa88d9b386c71bdc88bffc5273c08ada.tar.gz
#! nix-shell -p "haskell.packages.ghc923.ghcWithPackages (pkgs: with pkgs; [directory zlib unix filepath aeson process tar raw-strings-qq])" -j8
#! nix-shell -i "runhaskell"
{-# OPTIONS_GHC -fno-warn-unused-binds #-}
{-# OPTIONS_GHC -fno-warn-unused-imports #-}
{-# OPTIONS_GHC -fno-warn-unused-matches #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Main (main) where

import Control.Monad ()
import Data.Aeson ( decode, (.:), withObject, FromJSON(parseJSON) )
import Data.List ( intercalate )
import System.Directory ( createDirectoryIfMissing, listDirectory )
import System.FilePath ( (</>) )
import Text.RawString.QQ ( r )
import Data.ByteString.Lazy qualified as BS ( readFile, writeFile )
import qualified Data.ByteString.Lazy.Char8 as C ( pack )
import qualified Codec.Compression.GZip as GZip ( compress )
import Codec.Archive.Tar qualified as Tar ( pack, write )

data Template =
  Template
  { name :: String
  , path :: FilePath
  , output :: FilePath
  } deriving stock (Show)

instance FromJSON Template where
    parseJSON = withObject "Person" $ \v -> Template
        <$> v .: "name"
        <*> v .: "path"
        <*> v .: "output"

choice :: [Template] -> String
choice ts =
  [r|choose() { PS3='Choose your template: '|] ++
  "\noptions=(" ++ opts ++ " \"Quit\")\n" ++
  [r|select opt in "${options[@]}"; do case $opt in|] ++ "\n" ++
  mconcat (opt <$> ts) ++
  [r|"Quit") break ;; *) echo "invalid option $REPLY";; esac; done;}|]
    where
      opts = intercalate " " $ show . name <$> ts
      opt t = show (name t) ++ ") TAR=\"" ++ templateURL t ++ "\"; break ;;\n"

templateURL :: Template -> String
templateURL t = name t -- IDK what to put

tarPath :: Template -> IO ()
tarPath template = do
  putStrLn $ "Started : " <> template.name
  putStrLn "* Setup ouput directory"
  createDirectoryIfMissing True template.output

  putStrLn "* Tar-ing up"
  tar <- listDirectory template.path >>= Tar.pack template.path
  BS.writeFile (template.output </> template.name <> ".tar.gz")
    . GZip.compress $ Tar.write tar
  putStrLn "Done\n"

main :: IO ()
main = do
  Just (templates :: [Template]) <-
    decode <$> BS.readFile "./templates/export.json"
    
  mapM_ tarPath templates

  putStrLn "Generating choices"
  BS.writeFile "./choices" $ C.pack (choice templates)

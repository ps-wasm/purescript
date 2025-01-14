-- |
-- Parser for PSCI.
--
module Language.PureScript.Interactive.Parser
  ( parseDotFile
  , parseCommand
  ) where

import Prelude

import Control.Monad (join)
import Data.Bifunctor (bimap)
import Data.Char (isSpace)
import Data.List (intercalate)
import Data.List.NonEmpty qualified as NE
import Data.Text qualified as T
import Language.PureScript qualified as P
import Language.PureScript.CST qualified as CST
import Language.PureScript.CST.Monad qualified as CSTM
import Language.PureScript.Interactive.Directive qualified as D
import Language.PureScript.Interactive.Types

-- |
-- Parses a limited set of commands from from .purs-repl
--
parseDotFile :: FilePath -> String -> Either String [Command]
parseDotFile filePath =
  bimap (CST.prettyPrintError . NE.head) snd
    . CST.runTokenParser (parseMany parser <* CSTM.token CST.TokEof)
    . CST.lexTopLevel
    . T.pack
  where
  parser = CSTM.oneOf $ NE.fromList
    [ psciImport filePath
    , do
        tok <- CSTM.munch
        CSTM.parseFail tok $ CST.ErrCustom "The .purs-repl file only supports import declarations"
    ]

-- |
-- Parses PSCI metacommands or expressions input from the user.
--
parseCommand :: String -> Either String [Command]
parseCommand cmdString =
  case cmdString of
    (':' : cmd) -> pure <$> parseDirective cmd
    _ -> parseRest (mergeDecls <$> parseMany psciCommand) cmdString
  where
  mergeDecls (Decls as : bs) =
    case mergeDecls bs of
      Decls bs' : cs' ->
        Decls (as <> bs') : cs'
      cs' ->
        Decls as : cs'
  mergeDecls (a : bs) =
    a : mergeDecls bs
  mergeDecls [] = []

parseMany :: CST.Parser a -> CST.Parser [a]
parseMany = CSTM.manyDelimited CST.TokLayoutStart CST.TokLayoutEnd CST.TokLayoutSep

parseOne :: CST.Parser a -> CST.Parser a
parseOne p = CSTM.token CST.TokLayoutStart *> p <* CSTM.token CST.TokLayoutEnd

parseRest :: CST.Parser a -> String -> Either String a
parseRest p =
   bimap (CST.prettyPrintError . NE.head) snd
    . CST.runTokenParser (p <* CSTM.token CST.TokEof)
    . CST.lexTopLevel
    . T.pack

psciCommand :: CST.Parser Command
psciCommand =
  CSTM.oneOf $ NE.fromList
    [ psciImport ""
    , psciDeclaration
    , psciExpression
    ]

trim :: String -> String
trim = trimEnd . trimStart

trimStart :: String -> String
trimStart = dropWhile isSpace

trimEnd :: String -> String
trimEnd = reverse . trimStart . reverse

parseDirective :: String -> Either String Command
parseDirective cmd =
  case D.directivesFor' dstr of
    [(d, _)] -> commandFor d
    []       -> Left "Unrecognized directive. Type :? for help."
    ds       -> Left ("Ambiguous directive. Possible matches: " ++
                  intercalate ", " (map snd ds) ++ ". Type :? for help.")
  where
  (dstr, arg) = trim <$> break isSpace cmd

  commandFor d = case d of
    Help     -> return ShowHelp
    Quit     -> return QuitPSCi
    Reload   -> return ReloadState
    Clear    -> return ClearState
    Paste    -> return PasteLines
    Browse   -> BrowseModule . CST.nameValue <$> parseRest (parseOne CST.parseModuleNameP) arg
    Show     -> ShowInfo <$> parseReplQuery' arg
    Type     -> TypeOf . CST.convertExpr "" <$> parseRest (parseOne CST.parseExprP) arg
    Kind     -> KindOf . CST.convertType "" <$> parseRest (parseOne CST.parseTypeP) arg
    Complete -> return (CompleteStr arg)
    Print
      | arg == "" -> return $ ShowInfo QueryPrint
      | otherwise -> SetInteractivePrint <$> parseRest (parseOne parseFullyQualifiedIdent) arg

-- |
-- Parses expressions entered at the PSCI repl.
--
psciExpression :: CST.Parser Command
psciExpression = Expression . CST.convertExpr "" <$> CST.parseExprP

-- | Imports must be handled separately from other declarations, so that
-- :show import works, for example.
psciImport :: FilePath -> CST.Parser Command
psciImport filePath = do
  (_, mn, declType, asQ) <- CST.convertImportDecl filePath <$> CST.parseImportDeclP
  pure $ Import (mn, declType, asQ)

-- | Any declaration that we don't need a 'special case' parser for
-- (like import declarations).
psciDeclaration :: CST.Parser Command
psciDeclaration = Decls . CST.convertDeclaration "" <$> CST.parseDeclP

parseReplQuery' :: String -> Either String ReplQuery
parseReplQuery' str =
  case parseReplQuery str of
    Nothing -> Left ("Don't know how to show " ++ str ++ ". Try one of: " ++
                      intercalate ", " replQueryStrings ++ ".")
    Just query -> Right query

parseFullyQualifiedIdent :: CST.Parser (P.ModuleName, P.Ident)
parseFullyQualifiedIdent = join $ CST.Parser $ \st _ ksucc ->
  case CST.runParser st CST.parseQualIdentP of
    (st', Right (CST.QualifiedName _ (Just mn) ident)) ->
      ksucc st' $ pure (mn, P.Ident $ CST.getIdent ident)
    _ ->
      ksucc st $ do
        tok <- CSTM.munch
        CSTM.parseFail tok $ CST.ErrCustom "Expected a fully-qualified name (eg: PSCI.Support.eval)"

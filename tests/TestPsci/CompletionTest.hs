module TestPsci.CompletionTest where

import Prelude

import Test.Hspec

import Control.Monad.Trans.State.Strict (evalStateT)
import Data.Functor ((<&>))
import Data.List (sort)
import Data.Text qualified as T
import Language.PureScript qualified as P
import Language.PureScript.Interactive
import TestPsci.TestEnv (initTestPSCiEnv)
import TestUtils (getSupportModuleNames)

completionTests :: Spec
completionTests = context "completionTests" $
  beforeAll getPSCiStateForCompletion $
    mapM_ assertCompletedOk completionTestData

-- If the cursor is at the right end of the line, with the 1st element of the
-- pair as the text in the line, then pressing tab should offer all the
-- elements of the list (which is the 2nd element) as completions.
completionTestData :: [(String, IO [String])]
completionTestData =
  -- basic directives
  [ (":h",  pure [":help"])
  , (":r",  pure [":reload"])
  , (":c",  pure [":clear", ":complete"])
  , (":q",  pure [":quit"])
  , (":b",  pure [":browse"])

  -- :browse should complete module names
  , (":b Eff",    pure $ map (":b Effect" ++) ["", ".Unsafe", ".Class", ".Class.Console", ".Console", ".Uncurried", ".Ref"])
  , (":b Effect.", pure $ map (":b Effect" ++) [".Unsafe", ".Class", ".Class.Console", ".Console", ".Uncurried", ".Ref"])

  -- import should complete module names
  , ("import Eff",    pure $ map ("import Effect" ++) ["", ".Unsafe", ".Class", ".Class.Console", ".Console", ".Uncurried", ".Ref"])
  , ("import Effect.", pure $ map ("import Effect" ++) [".Unsafe", ".Class", ".Class.Console", ".Console", ".Uncurried", ".Ref"])

  -- :quit, :help, :reload, :clear should not complete
  , (":help ", pure [])
  , (":quit ", pure [])
  , (":reload ", pure [])
  , (":clear ", pure [])

  -- :show should complete its available arguments
  , (":show ", pure [":show import", ":show loaded", ":show print"])
  , (":show a", pure [])

  -- :type should complete next word from values and constructors in scope
  , (":type uni", pure [":type unit"])
  , (":type E", pure [":type EQ"])
  , (":type P.", pure $ map (":type P." ++) ["EQ", "GT", "LT", "unit"]) -- import Prelude (unit, Ordering(..)) as P
  , (":type Effect.Console.lo", pure [])
  , (":type voi", pure [])

  -- :kind should complete next word from types in scope
  , (":kind Str", pure [":kind String"])
  , (":kind ST.", pure [":kind ST.Region", ":kind ST.ST"]) -- import Control.Monad.ST as ST
  , (":kind STRef.", pure [":kind STRef.STRef"]) -- import Control.Monad.ST.Ref as STRef
  , (":kind Effect.", pure [])

  -- Only one argument for these directives should be completed
  , (":show import ", pure [])
  , (":browse Data.List ", pure [])

  -- These directives take any number of completable terms
  , (":type const compa", pure [":type const compare", ":type const comparing"])
  , (":kind Array In", pure [":kind Array Int"])

  -- a few other import tests
  , ("impor", pure ["import"])
  , ("import ", getSupportModuleNames <&> map (T.unpack . mappend "import "))
  , ("import Prelude ", pure [])

  -- String and number literals should not be completed
  , ("\"hi", pure [])
  , ("34", pure [])

  -- Identifiers and data constructors in scope should be completed
  , ("uni", pure ["unit"])
  , ("G", pure ["GT"])
  , ("P.G", pure ["P.GT"])
  , ("P.uni", pure ["P.unit"])
  , ("voi", pure []) -- import Prelude hiding (void)
  , ("Effect.Class.", pure [])

  -- complete first name after type annotation symbol
  , ("1 :: I", pure ["1 :: Int"])
  , ("1 ::I",  pure ["1 ::Int"])
  , ("1:: I",  pure ["1:: Int"])
  , ("1::I",   pure ["1::Int"])
  , ("(1::Int) uni", pure ["(1::Int) unit"]) -- back to completing values

  -- Parens and brackets aren't considered part of the current identifier
  , ("map id [uni", pure ["map id [unit"])
  , ("map (cons", pure ["map (const"])
  ]

assertCompletedOk :: (String, IO [String]) -> SpecWith PSCiState
assertCompletedOk (line, expectedsM) = specify line $ \psciState -> do
  expecteds <- expectedsM
  results <- runCM psciState (completion' (reverse line, ""))
  let actuals = formatCompletions results
  sort actuals `shouldBe` sort expecteds

runCM :: PSCiState -> CompletionM a -> IO a
runCM psciState act = evalStateT (liftCompletionM act) psciState

getPSCiStateForCompletion :: IO PSCiState
getPSCiStateForCompletion = do
  (st, _) <- initTestPSCiEnv
  let imports = [-- import Control.Monad.ST as S
                 (qualName "Control.Monad.ST"
                    ,P.Implicit
                    ,Just (qualName "ST"))
                , -- import Control.Monad.ST.Ref as STRef
                 (qualName "Control.Monad.ST.Ref"
                    ,P.Implicit
                    ,Just (qualName "STRef"))
                 -- import Prelude hiding (void)
                ,(qualName "Prelude"
                    ,P.Hiding [valName "void"]
                    ,Nothing)
                 -- import Prelude (unit, Ordering(..)) as P
                ,(qualName "Prelude"
                    ,P.Explicit [valName "unit", typeName "Ordering"]
                    ,Just (qualName "P"))]
  return $ updateImportedModules (const imports) st
  where
    qualName   = P.moduleNameFromString
    valName    = P.ValueRef srcSpan . P.Ident
    typeName t = P.TypeRef srcSpan (P.ProperName t) Nothing
    srcSpan    = P.internalModuleSourceSpan "<internal>"

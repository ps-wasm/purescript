module TestHierarchy where

import Prelude

import Language.PureScript.Hierarchy
import Language.PureScript qualified as P

import Test.Hspec

spec :: Spec
spec = describe "hierarchy" $ do
  describe "Language.PureScript.Hierarchy" $ do
    describe "prettyPrint" $ do
      it "creates just the node when there is no relation" $ do
        let superMap = SuperMap (Left $ P.ProperName "A")

        let prettyPrinted = prettyPrint superMap

        prettyPrinted `shouldBe` "  A;"

      it "creates a relation when there is one" $ do
        let superMap = SuperMap (Right (P.ProperName "A", P.ProperName "B"))

        let prettyPrinted = prettyPrint superMap

        prettyPrinted `shouldBe` "  A -> B;"

    describe "typeClassGraph" $ do
      it "doesn't generate a graph if there are no type classes" $ do
        let mainModule = P.Module
              (P.internalModuleSourceSpan "<hierarchy>")
              []
              (P.ModuleName "Main")
              []
              Nothing

        let graph = typeClassGraph mainModule

        graph `shouldBe` Nothing

      it "generates usable graphviz graphs" $ do
        let declarations =
              [ P.TypeClassDeclaration
                 (P.internalModuleSourceSpan "<A>", [])
                 (P.ProperName "A")
                 []
                 []
                 []
                 []
              , P.TypeClassDeclaration
                 (P.internalModuleSourceSpan "<B>", [])
                 (P.ProperName "B")
                 []
                 [P.srcConstraint (P.Qualified P.ByNullSourcePos $ P.ProperName "A") [] [] Nothing]
                 []
                 []
              ]
        let mainModule = P.Module
              (P.internalModuleSourceSpan "<hierarchy>")
              []
              (P.ModuleName "Main")
              declarations
              Nothing

        let graph = typeClassGraph mainModule

        graph `shouldBe` Just (Graph (GraphName "Main") (Digraph "digraph Main {\n  A;\n  A -> B;\n}"))

prettyConstr c = case c of
  CanonSubtype a1 a2 ->
    prettyAnn a1 ++ " < " ++ prettyAnn a2

  CanonCanBeMatchedBy a1 real ->
    prettyAnn a1 ++ " < " ++ prettyReal real

  CanonImpl (a1, real) (a2, a3) ->
    "(" ++ prettyReal real ++ " < " ++ prettyAnn a1 ++ ") => ("
      ++ prettyAnn a2 ++ " < " ++ prettyAnn a3 ++ ")"

  CanonForall a1 real a2 ->
    "(∀ x∈" ++ prettyAnn a1 ++ " . x < " ++ prettyReal real ++ "=> x < " ++ prettyAnn a2 ++ ")"

  CanonPatEq a1 pat a2 ->
    "(" ++ prettyAnn a2 ++ " == " ++ prettyStrInPattern pat (prettyAnn a1) ++ ")"




prettyEntry (s, (ann, vars, constrs )) =
    s ++ " :: " ++
    (if null vars then "" else "∀ " ++ (List.intercalate " " $ map show vars) ++ " .\n\t")
    ++ (if null constrs then "" else "(" ++ (List.intercalate ",\n\t" $ map prettyConstr constrs) ++ ") =>\n\t\t" )
    ++ prettyAnn ann

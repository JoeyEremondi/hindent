module Main (..) where


ratio =
  graphHeight
    / (if range == 0 then
        0.1
       else
        toFloat range
      )



-- foo=(case x of {True->1;False->3})


bar =
  (if
    if a then
      True
    else
      False
   then
    "a"
   else
    "b"
  )


multilineList =
  [ 1
  , 2
  , 3
  ]


singlelineList =
  [ 1, 2, 3 ]


longList =
  [ 5076944270305263616
  , 6273267784164048896
  , -7613292870346211328
  ]

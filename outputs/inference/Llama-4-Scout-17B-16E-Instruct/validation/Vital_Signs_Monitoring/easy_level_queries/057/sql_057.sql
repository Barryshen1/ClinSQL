SELECT 
  itemid, 
  label
FROM 
  `physionet-data.mimiciv_3_1_icu.d_items`
WHERE 
  label LIKE '%Respiratory Rate%';
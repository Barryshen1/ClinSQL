SELECT 
  itemid, 
  label 
FROM 
  `physionet-data.mimiciv_3_1_icu`.d_items 
WHERE 
  category = 'Ultrasound' OR label LIKE '%echocardi%';
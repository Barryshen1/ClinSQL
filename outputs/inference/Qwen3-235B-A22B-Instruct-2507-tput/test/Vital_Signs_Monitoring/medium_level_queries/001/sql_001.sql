SELECT itemid, label, unitname 
FROM `physionet-data.mimiciv_3_1_icu.d_items` 
WHERE LOWER(label) LIKE '%systolic%' 
  AND LOWER(category) LIKE '%blood pressure%'
  AND LOWER(unitname) = 'mm hg';
SELECT itemid, label 
   FROM `physionet-data.mimiciv_3_1_icu.d_items`
   WHERE label LIKE '%dialysis%' OR label LIKE '%renal replacement%' OR label LIKE '%CRRT%';
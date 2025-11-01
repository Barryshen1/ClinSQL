SELECT itemid, label, unitname 
   FROM `physionet-data.mimiciv_3_1_icu.d_items` 
   WHERE category = 'Vital Signs' AND label LIKE '%Temperature%' AND unitname = 'C';
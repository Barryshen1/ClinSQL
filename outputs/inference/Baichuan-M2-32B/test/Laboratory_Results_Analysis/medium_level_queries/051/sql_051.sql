WITH hs_tnt_item AS (
     SELECT itemid
     FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
     WHERE label LIKE '%hs-TnT%' OR label LIKE '%high-sensitivity troponin T%'
       AND category IN ('Cardiac', 'Troponin')
     ORDER BY itemid
     LIMIT 1
   );
WITH 
  -- Find itemid for hs-TnT
  hs_tnt_itemid AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
    WHERE label LIKE '%hs-TnT%'
  ),
  
  -- Get first hs-TnT for each admission
  first_hs_tnt AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      le.valuenum AS first_hs_tnt_value
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON a.hadm_id = le.hadm_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 59 AND 69
      AND le.itemid IN (SELECT itemid FROM hs_tnt_itemid)
      AND le.charttime = (
        SELECT MIN(charttime) 
        FROM `physionet-data.mimiciv_3_1_hosp.labevents` le2 
        WHERE le2.hadm_id = a.hadm_id AND le2.itemid IN (SELECT itemid FROM hs_tnt_itemid)
      )
  )
SELECT 
  APPROX_QUANTILES(first_hs_tnt_value, 4)[0] AS p25,
  APPROX_QUANTILES(first_hs_tnt_value, 4)[1] AS p50,
  APPROX_QUANTILES(first_hs_tnt_value, 4)[2] AS p75,
  MIN(first_hs_tnt_value) AS min_value,
  MAX(first_hs_tnt_value) AS max_value
FROM 
  first_hs_tnt
WHERE 
  first_hs_tnt_value > 0.014;
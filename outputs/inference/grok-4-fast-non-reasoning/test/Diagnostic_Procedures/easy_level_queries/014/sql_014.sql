WITH mcs_items AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%balloon%' 
     OR LOWER(label) LIKE '%impella%' 
     OR LOWER(label) LIKE '%assist device%' 
     OR LOWER(label) LIKE '%vad%'
),
eligible_admissions AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
)
SELECT
  APPROX_QUANTILES(mcs_count, 2)[OFFSET(1)] AS median_mcs_devices
FROM (
  SELECT hadm_id, COUNT(DISTINCT ie.itemid) AS mcs_count
  FROM eligible_admissions ea
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie 
    ON ea.hadm_id = ie.hadm_id
  INNER JOIN mcs_items mi ON ie.itemid = mi.itemid
  WHERE ie.amount > 0
    AND (ie.ordercategoryname LIKE '%Infusion%' OR ie.ordercategoryname LIKE '%Support%')
  GROUP BY hadm_id
  
  UNION ALL
  
  -- Include hospitalizations with 0 MCS devices
  SELECT hadm_id, 0 AS mcs_count
  FROM eligible_admissions ea
  WHERE hadm_id NOT IN (
    SELECT ea2.hadm_id
    FROM eligible_admissions ea2
    INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie ON ea2.hadm_id = ie.hadm_id
    INNER JOIN mcs_items mi ON ie.itemid = mi.itemid
    WHERE ie.amount > 0
      AND (ie.ordercategoryname LIKE '%Infusion%' OR ie.ordercategoryname LIKE '%Support%')
  )
) sub;
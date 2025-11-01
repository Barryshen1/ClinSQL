WITH cohort AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND (a.dischtime - a.admittime) >= INTERVAL 72 HOUR
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_code LIKE 'E11%'
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_code LIKE 'I50%'
    )
),

prescriptions_with_categories AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    p.starttime,
    p.drug,
    CASE
      WHEN p.drug LIKE '%Glargine%' OR p.drug LIKE '%Detemir%' OR p.drug LIKE '%NPH%' THEN 'basal'
      WHEN p.drug LIKE '%Lispro%' OR p.drug LIKE '%Aspart%' OR (p.drug LIKE '%Regular%' AND p.drug NOT LIKE '%Sliding Scale%') THEN 'bolus'
      WHEN p.drug LIKE '%Sliding Scale%' THEN 'sliding_scale'
      ELSE NULL
    END AS insulin_type
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON c.hadm_id = p.hadm_id
  WHERE p.starttime IS NOT NULL
    AND p.drug IS NOT NULL
),

window_flags AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN insulin_type = 'basal' AND starttime BETWEEN admittime AND admittime + INTERVAL 72 HOUR THEN 1 ELSE 0 END) AS basal_first72,
    MAX(CASE WHEN insulin_type = 'bolus' AND starttime BETWEEN admittime AND admittime + INTERVAL 72 HOUR THEN 1 ELSE 0 END) AS bolus_first72,
    MAX(CASE WHEN insulin_type = 'sliding_scale' AND starttime BETWEEN admittime AND admittime + INTERVAL 72 HOUR THEN 1 ELSE 0 END) AS sliding_first72,
    MAX(CASE WHEN insulin_type = 'basal' AND starttime BETWEEN dischtime - INTERVAL 48 HOUR AND dischtime THEN 1 ELSE 0 END) AS basal_final48,
    MAX(CASE WHEN insulin_type = 'bolus' AND starttime BETWEEN dischtime - INTERVAL 48 HOUR AND dischtime THEN 1 ELSE 0 END) AS bolus_final48,
    MAX(CASE WHEN insulin_type = 'sliding_scale' AND starttime BETWEEN dischtime - INTERVAL 48 HOUR AND dischtime THEN 1 ELSE 0 END) AS sliding_final48
  FROM prescriptions_with_categories
  GROUP BY hadm_id
)

SELECT
  AVG(basal_first72) * 100 AS basal_first72_pct,
  AVG(basal_final48) * 100 AS basal_final48_pct,
  (AVG(basal_first72) - AVG(basal_final48)) * 100 AS basal_diff,
  AVG(bolus_first72) * 100 AS bolus_first72_pct,
  AVG(bolus_final48) * 100 AS bolus_final48_pct,
  (AVG(bolus_first72) - AVG(bolus_final48)) * 100 AS bolus_diff,
  AVG(sliding_first72) * 100 AS sliding_first72_pct,
  AVG(sliding_final48) * 100 AS sliding_final48_pct,
  (AVG(sliding_first72) - AVG(sliding_final48)) * 100 AS sliding_diff,
  AVG(basal_first72 * bolus_first72) * 100 AS basal_bolus_first72_pct,
  AVG(basal_final48 * bolus_final48) * 100 AS basal_bolus_final48_pct,
  (AVG(basal_first72 * bolus_first72) - AVG(basal_final48 * bolus_final48)) * 100 AS basal_bolus_diff
FROM window_flags;
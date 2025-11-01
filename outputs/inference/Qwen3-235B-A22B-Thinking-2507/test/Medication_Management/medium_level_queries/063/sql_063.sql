WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    -- Age at admission: 45-55 years
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 45 AND 55
    -- Diabetes diagnosis (ICD-9/10)
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'E08%' 
              OR d.icd_code LIKE 'E09%' 
              OR d.icd_code LIKE 'E10%' 
              OR d.icd_code LIKE 'E11%' 
              OR d.icd_code LIKE 'E13%')
        )
    )
    -- Heart failure diagnosis (ICD-9/10)
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
insulin_times AS (
  -- Insulin from prescriptions (any route)
  SELECT hadm_id, starttime AS insulin_time
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%insulin%'
    AND starttime IS NOT NULL
  UNION ALL
  -- Insulin from ICU inputevents
  SELECT i.hadm_id, i.starttime
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON i.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%insulin%'
    AND i.starttime IS NOT NULL
),
first_insulin AS (
  SELECT hadm_id, MIN(insulin_time) AS first_insulin_time
  FROM insulin_times
  GROUP BY hadm_id
),
oral_times AS (
  -- Oral antidiabetics (only oral route)
  SELECT hadm_id, starttime AS oral_time
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(route) = 'oral'
    AND starttime IS NOT NULL
    AND (
      LOWER(drug) LIKE '%metformin%'
      OR LOWER(drug) LIKE '%glipizide%'
      OR LOWER(drug) LIKE '%glyburide%'
      OR LOWER(drug) LIKE '%glimepiride%'
      OR LOWER(drug) LIKE '%sitagliptin%'
      OR LOWER(drug) LIKE '%saxagliptin%'
      OR LOWER(drug) LIKE '%linagliptin%'
      OR LOWER(drug) LIKE '%pioglitazone%'
      OR LOWER(drug) LIKE '%repaglinide%'
      OR LOWER(drug) LIKE '%canagliflozin%'
      OR LOWER(drug) LIKE '%dapagliflozin%'
      OR LOWER(drug) LIKE '%empagliflozin%'
      OR LOWER(drug) LIKE '%acarbose%'
    )
),
first_oral AS (
  SELECT hadm_id, MIN(oral_time) AS first_oral_time
  FROM oral_times
  GROUP BY hadm_id
),
flags AS (
  SELECT 
    c.hadm_id,
    -- Insulin flags
    CASE WHEN fi.first_insulin_time >= c.admittime 
          AND fi.first_insulin_time <= c.admittime + INTERVAL '12' HOUR 
         THEN 1 ELSE 0 END AS insulin_first12,
    CASE WHEN fi.first_insulin_time >= c.dischtime - INTERVAL '72' HOUR 
          AND fi.first_insulin_time <= c.dischtime 
         THEN 1 ELSE 0 END AS insulin_final72,
    -- Oral antidiabetics flags
    CASE WHEN fo.first_oral_time >= c.admittime 
          AND fo.first_oral_time <= c.admittime + INTERVAL '12' HOUR 
         THEN 1 ELSE 0 END AS oral_first12,
    CASE WHEN fo.first_oral_time >= c.dischtime - INTERVAL '72' HOUR 
          AND fo.first_oral_time <= c.dischtime 
         THEN 1 ELSE 0 END AS oral_final72
  FROM cohort c
  LEFT JOIN first_insulin fi ON c.hadm_id = fi.hadm_id
  LEFT JOIN first_oral fo ON c.hadm_id = fo.hadm_id
)
SELECT 
  -- Insulin rates (%)
  SUM(insulin_first12) * 100.0 / COUNT(*) AS insulin_first12_rate,
  SUM(insulin_final72) * 100.0 / COUNT(*) AS insulin_final72_rate,
  (SUM(insulin_first12) * 100.0 / COUNT(*) - SUM(insulin_final72) * 100.0 / COUNT(*)) AS insulin_diff,
  -- Oral antidiabetics rates (%)
  SUM(oral_first12) * 100.0 / COUNT(*) AS oral_first12_rate,
  SUM(oral_final72) * 100.0 / COUNT(*) AS oral_final72_rate,
  (SUM(oral_first12) * 100.0 / COUNT(*) - SUM(oral_final72) * 100.0 / COUNT(*)) AS oral_diff
FROM flags;
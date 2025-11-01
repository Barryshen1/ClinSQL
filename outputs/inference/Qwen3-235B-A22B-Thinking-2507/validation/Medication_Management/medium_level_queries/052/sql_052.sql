WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 45 AND 55
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 48
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
          OR (d.icd_version = 9 AND LENGTH(d.icd_code) = 5 AND SUBSTR(d.icd_code, 5, 1) IN ('0', '2'))
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
          OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
        )
    )
),
med_flags AS (
  SELECT 
    c.hadm_id,
    MAX(CASE 
          WHEN p.starttime >= c.admittime 
            AND p.starttime < DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
            AND LOWER(p.drug) LIKE '%insulin%' 
          THEN 1 ELSE 0 
        END) AS insulin_first_48h,
    MAX(CASE 
          WHEN p.starttime >= c.admittime 
            AND p.starttime < DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
            AND LOWER(p.route) LIKE '%oral%' 
            AND (
              LOWER(p.drug) LIKE '%metformin%' OR
              LOWER(p.drug) LIKE '%glipizide%' OR
              LOWER(p.drug) LIKE '%glyburide%' OR
              LOWER(p.drug) LIKE '%glimepiride%' OR
              LOWER(p.drug) LIKE '%sitagliptin%' OR
              LOWER(p.drug) LIKE '%saxagliptin%' OR
              LOWER(p.drug) LIKE '%linagliptin%' OR
              LOWER(p.drug) LIKE '%alogliptin%' OR
              LOWER(p.drug) LIKE '%canagliflozin%' OR
              LOWER(p.drug) LIKE '%dapagliflozin%' OR
              LOWER(p.drug) LIKE '%empagliflozin%' OR
              LOWER(p.drug) LIKE '%ertugliflozin%' OR
              LOWER(p.drug) LIKE '%pioglitazone%' OR
              LOWER(p.drug) LIKE '%rosiglitazone%' OR
              LOWER(p.drug) LIKE '%acarbose%' OR
              LOWER(p.drug) LIKE '%miglitol%' OR
              LOWER(p.drug) LIKE '%repaglinide%' OR
              LOWER(p.drug) LIKE '%nateglinide%'
            )
          THEN 1 ELSE 0 
        END) AS oral_first_48h,
    MAX(CASE 
          WHEN p.starttime >= DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR)
            AND p.starttime <= c.dischtime
            AND LOWER(p.drug) LIKE '%insulin%' 
          THEN 1 ELSE 0 
        END) AS insulin_last_24h,
    MAX(CASE 
          WHEN p.starttime >= DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR)
            AND p.starttime <= c.dischtime
            AND LOWER(p.route) LIKE '%oral%' 
            AND (
              LOWER(p.drug) LIKE '%metformin%' OR
              LOWER(p.drug) LIKE '%glipizide%' OR
              LOWER(p.drug) LIKE '%glyburide%' OR
              LOWER(p.drug) LIKE '%glimepiride%' OR
              LOWER(p.drug) LIKE '%sitagliptin%' OR
              LOWER(p.drug) LIKE '%saxagliptin%' OR
              LOWER(p.drug) LIKE '%linagliptin%' OR
              LOWER(p.drug) LIKE '%alogliptin%' OR
              LOWER(p.drug) LIKE '%canagliflozin%' OR
              LOWER(p.drug) LIKE '%dapagliflozin%' OR
              LOWER(p.drug) LIKE '%empagliflozin%' OR
              LOWER(p.drug) LIKE '%ertugliflozin%' OR
              LOWER(p.drug) LIKE '%pioglitazone%' OR
              LOWER(p.drug) LIKE '%rosiglitazone%' OR
              LOWER(p.drug) LIKE '%acarbose%' OR
              LOWER(p.drug) LIKE '%miglitol%' OR
              LOWER(p.drug) LIKE '%repaglinide%' OR
              LOWER(p.drug) LIKE '%nateglinide%'
            )
          THEN 1 ELSE 0 
        END) AS oral_last_24h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  GROUP BY c.hadm_id
)
SELECT 
  'first_48h' AS time_window,
  AVG(insulin_first_48h) * 100 AS insulin_pct,
  AVG(oral_first_48h) * 100 AS oral_pct
FROM med_flags
UNION ALL
SELECT 
  'last_24h',
  AVG(insulin_last_24h) * 100,
  AVG(oral_last_24h) * 100
FROM med_flags;
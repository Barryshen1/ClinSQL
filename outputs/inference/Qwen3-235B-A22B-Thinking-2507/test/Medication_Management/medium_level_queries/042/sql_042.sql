WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 51 AND 61
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR 
          (d.icd_version = 10 AND (d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%'))
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR 
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),

meds AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    CASE WHEN LOWER(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 END AS is_insulin,
    CASE WHEN p.route = 'ORAL' 
          AND ( 
            LOWER(p.drug) LIKE '%metformin%' 
            OR LOWER(p.drug) LIKE '%glipizide%'
            OR LOWER(p.drug) LIKE '%glyburide%'
            OR LOWER(p.drug) LIKE '%glimepiride%'
            OR LOWER(p.drug) LIKE '%sitagliptin%'
            OR LOWER(p.drug) LIKE '%saxagliptin%'
            OR LOWER(p.drug) LIKE '%linagliptin%'
            OR LOWER(p.drug) LIKE '%alogliptin%'
            OR LOWER(p.drug) LIKE '%canagliflozin%'
            OR LOWER(p.drug) LIKE '%dapagliflozin%'
            OR LOWER(p.drug) LIKE '%empagliflozin%'
            OR LOWER(p.drug) LIKE '%ertugliflozin%'
            OR LOWER(p.drug) LIKE '%pioglitazone%'
            OR LOWER(p.drug) LIKE '%rosiglitazone%'
            OR LOWER(p.drug) LIKE '%repaglinide%'
            OR LOWER(p.drug) LIKE '%nateglinide%'
            OR LOWER(p.drug) LIKE '%acarbose%'
            OR LOWER(p.drug) LIKE '%miglitol%'
            OR LOWER(p.drug) LIKE '%chlorpropamide%'
            OR LOWER(p.drug) LIKE '%tolazamide%'
            OR LOWER(p.drug) LIKE '%tolbutamide%'
            OR LOWER(p.drug) LIKE '%troglitazone%'
          ) THEN 1 ELSE 0 END AS is_oral
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE 
    (LOWER(p.drug) LIKE '%insulin%') 
    OR 
    (p.route = 'ORAL' 
      AND ( 
        LOWER(p.drug) LIKE '%metformin%' 
        OR LOWER(p.drug) LIKE '%glipizide%'
        OR LOWER(p.drug) LIKE '%glyburide%'
        OR LOWER(p.drug) LIKE '%glimepiride%'
        OR LOWER(p.drug) LIKE '%sitagliptin%'
        OR LOWER(p.drug) LIKE '%saxagliptin%'
        OR LOWER(p.drug) LIKE '%linagliptin%'
        OR LOWER(p.drug) LIKE '%alogliptin%'
        OR LOWER(p.drug) LIKE '%canagliflozin%'
        OR LOWER(p.drug) LIKE '%dapagliflozin%'
        OR LOWER(p.drug) LIKE '%empagliflozin%'
        OR LOWER(p.drug) LIKE '%ertugliflozin%'
        OR LOWER(p.drug) LIKE '%pioglitazone%'
        OR LOWER(p.drug) LIKE '%rosiglitazone%'
        OR LOWER(p.drug) LIKE '%repaglinide%'
        OR LOWER(p.drug) LIKE '%nateglinide%'
        OR LOWER(p.drug) LIKE '%acarbose%'
        OR LOWER(p.drug) LIKE '%miglitol%'
        OR LOWER(p.drug) LIKE '%chlorpropamide%'
        OR LOWER(p.drug) LIKE '%tolazamide%'
        OR LOWER(p.drug) LIKE '%tolbutamide%'
        OR LOWER(p.drug) LIKE '%troglitazone%'
      )
    )
),

med_usage AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    -- First 48h window
    MAX(CASE WHEN m.is_insulin = 1 
              AND m.starttime < LEAST(c.admittime + INTERVAL '48' HOUR, c.dischtime)
              AND COALESCE(m.stoptime, c.dischtime) > c.admittime 
             THEN 1 ELSE 0 END) AS first_48h_insulin,
    MAX(CASE WHEN m.is_oral = 1 
              AND m.starttime < LEAST(c.admittime + INTERVAL '48' HOUR, c.dischtime)
              AND COALESCE(m.stoptime, c.dischtime) > c.admittime 
             THEN 1 ELSE 0 END) AS first_48h_oral,
    -- Final 24h window
    MAX(CASE WHEN m.is_insulin = 1 
              AND m.starttime < c.dischtime
              AND COALESCE(m.stoptime, c.dischtime) > GREATEST(c.dischtime - INTERVAL '24' HOUR, c.admittime)
             THEN 1 ELSE 0 END) AS final_24h_insulin,
    MAX(CASE WHEN m.is_oral = 1 
              AND m.starttime < c.dischtime
              AND COALESCE(m.stoptime, c.dischtime) > GREATEST(c.dischtime - INTERVAL '24' HOUR, c.admittime)
             THEN 1 ELSE 0 END) AS final_24h_oral
  FROM cohort c
  LEFT JOIN meds m 
    ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
  GROUP BY c.subject_id, c.hadm_id
)

SELECT
  COUNT(*) AS total_patients,
  -- First 48h percentages
  SUM(first_48h_insulin) * 100.0 / COUNT(*) AS pct_insulin_first_48h,
  SUM(first_48h_oral) * 100.0 / COUNT(*) AS pct_oral_first_48h,
  -- Final 24h percentages
  SUM(final_24h_insulin) * 100.0 / COUNT(*) AS pct_insulin_final_24h,
  SUM(final_24h_oral) * 100.0 / COUNT(*) AS pct_oral_final_24h,
  -- Insulin changes
  SUM(CASE WHEN first_48h_insulin = 1 AND final_24h_insulin = 1 THEN 1 ELSE 0 END) AS insulin_continued,
  SUM(CASE WHEN first_48h_insulin = 0 AND final_24h_insulin = 1 THEN 1 ELSE 0 END) AS insulin_initiated,
  SUM(CASE WHEN first_48h_insulin = 1 AND final_24h_insulin = 0 THEN 1 ELSE 0 END) AS insulin_discontinued,
  -- Oral agent changes
  SUM(CASE WHEN first_48h_oral = 1 AND final_24h_oral = 1 THEN 1 ELSE 0 END) AS oral_continued,
  SUM(CASE WHEN first_48h_oral = 0 AND final_24h_oral = 1 THEN 1 ELSE 0 END) AS oral_initiated,
  SUM(CASE WHEN first_48h_oral = 1 AND final_24h_oral = 0 THEN 1 ELSE 0 END) AS oral_discontinued
FROM med_usage;
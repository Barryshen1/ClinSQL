WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - 2008 AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.hadm_id IS NOT NULL
    AND a.admission_type != 'OBSERVATION'
    AND a.dischtime > a.admittime  -- Valid stays only
),
cohort_with_dx AS (
  SELECT 
    c.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        WHERE d.hadm_id = c.hadm_id 
          AND (
            (d.icd_version = 10 AND d.icd_code LIKE 'E11%') 
            OR (d.icd_version = 9 AND d.icd_code LIKE '250%')
          )
      ) THEN 1 ELSE 0 
    END AS has_t2d,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        WHERE d.hadm_id = c.hadm_id 
          AND (
            (d.icd_version = 10 AND d.icd_code LIKE 'I50%') 
            OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
          )
      ) THEN 1 ELSE 0 
    END AS has_hf
  FROM cohort c
  WHERE c.age_at_admit BETWEEN 38 AND 48
),
final_cohort AS (
  SELECT hadm_id, admittime, dischtime
  FROM cohort_with_dx 
  WHERE has_t2d = 1 AND has_hf = 1
),
insulin_starts AS (
  SELECT 
    pr.hadm_id, 
    MIN(pr.starttime) AS min_start_insulin
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN final_cohort fc ON pr.hadm_id = fc.hadm_id
  WHERE LOWER(pr.drug) LIKE '%insulin%'
    AND pr.starttime IS NOT NULL
  GROUP BY pr.hadm_id
),
oral_starts AS (
  SELECT 
    pr.hadm_id, 
    MIN(pr.starttime) AS min_start_oral
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN final_cohort fc ON pr.hadm_id = fc.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND (
      LOWER(pr.drug) LIKE '%metformin%' OR
      LOWER(pr.drug) LIKE '%glipizide%' OR
      LOWER(pr.drug) LIKE '%glyburide%' OR
      LOWER(pr.drug) LIKE '%glimepiride%' OR
      LOWER(pr.drug) LIKE '%pioglitazone%' OR
      LOWER(pr.drug) LIKE '%rosiglitazone%' OR
      LOWER(pr.drug) LIKE '%sitagliptin%' OR
      LOWER(pr.drug) LIKE '%linagliptin%' OR
      LOWER(pr.drug) LIKE '%saxagliptin%' OR
      LOWER(pr.drug) LIKE '%alogliptin%' OR
      LOWER(pr.drug) LIKE '%empagliflozin%' OR
      LOWER(pr.drug) LIKE '%dapagliflozin%' OR
      LOWER(pr.drug) LIKE '%canagliflozin%' OR
      LOWER(pr.drug) LIKE '%ertugliflozin%' OR
      LOWER(pr.drug) LIKE '%acarbose%' OR
      LOWER(pr.drug) LIKE '%miglitol%' OR
      LOWER(pr.drug) LIKE '%repaglinide%' OR
      LOWER(pr.drug) LIKE '%nateglinide%' OR
      LOWER(pr.drug) LIKE '%chlorpropamide%'
    )
  GROUP BY pr.hadm_id
)
SELECT 
  COUNT(*) AS total_patients,
  ROUND(100.0 * COUNT(CASE 
    WHEN i.min_start_insulin >= fc.admittime 
      AND i.min_start_insulin < TIMESTAMP_ADD(fc.admittime, INTERVAL 72 HOUR) 
    THEN 1 
  END) / NULLIF(COUNT(*), 0), 1) AS pct_insulin_first72,
  ROUND(100.0 * COUNT(CASE 
    WHEN o.min_start_oral >= fc.admittime 
      AND o.min_start_oral < TIMESTAMP_ADD(fc.admittime, INTERVAL 72 HOUR) 
    THEN 1 
  END) / NULLIF(COUNT(*), 0), 1) AS pct_oral_first72,
  ROUND(100.0 * COUNT(CASE 
    WHEN i.min_start_insulin > TIMESTAMP_SUB(fc.dischtime, INTERVAL 72 HOUR) 
      AND i.min_start_insulin <= fc.dischtime 
    THEN 1 
  END) / NULLIF(COUNT(*), 0), 1) AS pct_insulin_final72,
  ROUND(100.0 * COUNT(CASE 
    WHEN o.min_start_oral > TIMESTAMP_SUB(fc.dischtime, INTERVAL 72 HOUR) 
      AND o.min_start_oral <= fc.dischtime 
    THEN 1 
  END) / NULLIF(COUNT(*), 0), 1) AS pct_oral_final72
FROM final_cohort fc
LEFT JOIN insulin_starts i ON fc.hadm_id = i.hadm_id
LEFT JOIN oral_starts o ON fc.hadm_id = o.hadm_id;
WITH cohort AS (
  SELECT DISTINCT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 38 AND 48
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9  AND di.icd_code LIKE '250%')
          OR (di.icd_version = 10 AND di.icd_code LIKE 'E11%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di2
      WHERE di2.subject_id = a.subject_id
        AND di2.hadm_id = a.hadm_id
        AND (
          (di2.icd_version = 9  AND di2.icd_code LIKE '428%')
          OR (di2.icd_version = 10 AND di2.icd_code LIKE 'I50%')
        )
    )
),

first72_insulin AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = c.hadm_id AND a.subject_id = c.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
  WHERE p.starttime >= a.admittime
    AND p.starttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND (
      LOWER(p.drug) LIKE '%insulin%'
      OR LOWER(p.drug_type) LIKE '%insulin%'
    )
),

final72_insulin AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = c.hadm_id AND a.subject_id = c.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
  WHERE p.starttime >= TIMESTAMP_SUB(a.dischtime, INTERVAL 72 HOUR)
    AND p.starttime < a.dischtime
    AND (
      LOWER(p.drug) LIKE '%insulin%'
      OR LOWER(p.drug_type) LIKE '%insulin%'
    )
),

first72_oral AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = c.hadm_id AND a.subject_id = c.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
  WHERE p.starttime >= a.admittime
    AND p.starttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND (
      LOWER(p.drug) LIKE '%metformin%' OR
      LOWER(p.drug) LIKE '%glipizide%' OR
      LOWER(p.drug) LIKE '%glyburide%' OR
      LOWER(p.drug) LIKE '%glimepiride%' OR
      LOWER(p.drug) LIKE '%pioglitazone%' OR
      LOWER(p.drug) LIKE '%rosiglitazone%' OR
      LOWER(p.drug) LIKE '%sitagliptin%' OR
      LOWER(p.drug) LIKE '%linagliptin%' OR
      LOWER(p.drug) LIKE '%empagliflozin%' OR
      LOWER(p.drug) LIKE '%dapagliflozin%' OR
      LOWER(p.drug) LIKE '%canagliflozin%' OR
      LOWER(p.drug) LIKE '%acarbose%' OR
      LOWER(p.drug) LIKE '%repaglinide%' OR
      LOWER(p.drug) LIKE '%nateglinide%'
    )
),

final_oral AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = c.hadm_id AND a.subject_id = c.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
  WHERE p.starttime >= TIMESTAMP_SUB(a.dischtime, INTERVAL 72 HOUR)
    AND p.starttime < a.dischtime
    AND (
      LOWER(p.drug) LIKE '%metformin%' OR
      LOWER(p.drug) LIKE '%glipizide%' OR
      LOWER(p.drug) LIKE '%glyburide%' OR
      LOWER(p.drug) LIKE '%glimepiride%' OR
      LOWER(p.drug) LIKE '%pioglitazone%' OR
      LOWER(p.drug) LIKE '%rosiglitazone%' OR
      LOWER(p.drug) LIKE '%sitagliptin%' OR
      LOWER(p.drug) LIKE '%linagliptin%' OR
      LOWER(p.drug) LIKE '%empagliflozin%' OR
      LOWER(p.drug) LIKE '%dapagliflozin%' OR
      LOWER(p.drug) LIKE '%canagliflozin%' OR
      LOWER(p.drug) LIKE '%acarbose%' OR
      LOWER(p.drug) LIKE '%repaglinide%' OR
      LOWER(p.drug) LIKE '%nateglinide%'
    )
)

SELECT
  (SELECT COUNT(*) FROM cohort) AS total_cohort,
  (SELECT COUNT(*) FROM first72_insulin) AS first72_insulin_count,
  (SELECT COUNT(*) FROM first72_oral) AS first72_oral_count,
  (SELECT COUNT(*) FROM final72_insulin) AS final72_insulin_count,
  (SELECT COUNT(*) FROM final_oral) AS final72_oral_count,
  SAFE_DIVIDE((SELECT COUNT(*) FROM first72_insulin),
              (SELECT COUNT(*) FROM cohort)) * 100 AS first72_insulin_pct,
  SAFE_DIVIDE((SELECT COUNT(*) FROM first72_oral),
              (SELECT COUNT(*) FROM cohort)) * 100 AS first72_oral_pct,
  SAFE_DIVIDE((SELECT COUNT(*) FROM final72_insulin),
              (SELECT COUNT(*) FROM cohort)) * 100 AS final72_insulin_pct,
  SAFE_DIVIDE((SELECT COUNT(*) FROM final_oral),
              (SELECT COUNT(*) FROM cohort)) * 100 AS final72_oral_pct
FROM cohort
LIMIT 1;
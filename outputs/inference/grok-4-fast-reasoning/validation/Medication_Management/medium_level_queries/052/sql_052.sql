WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 10 AND di.icd_code LIKE 'E11%') OR
          (di.icd_version = 9 AND di.icd_code LIKE '250%' AND SUBSTR(di.icd_code, 4, 1) IN ('0', '2', '4', '6', '8'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` hf
      WHERE hf.subject_id = a.subject_id
        AND hf.hadm_id = a.hadm_id
        AND (
          (hf.icd_version = 10 AND hf.icd_code LIKE 'I50%') OR
          (hf.icd_version = 9 AND hf.icd_code LIKE '428%')
        )
    )
),
insulin_first AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.emar` e
    WHERE e.subject_id = c.subject_id
      AND e.hadm_id = c.hadm_id
      AND e.charttime >= c.admittime
      AND e.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
      AND LOWER(e.medication) LIKE '%insulin%'
  )
),
oral_first AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.emar` e
    WHERE e.subject_id = c.subject_id
      AND e.hadm_id = c.hadm_id
      AND e.charttime >= c.admittime
      AND e.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
      AND (
        LOWER(e.medication) LIKE '%metformin%'
        OR LOWER(e.medication) LIKE '%glipizide%'
        OR LOWER(e.medication) LIKE '%glyburide%'
        OR LOWER(e.medication) LIKE '%glimepiride%'
        OR LOWER(e.medication) LIKE '%pioglitazone%'
        OR LOWER(e.medication) LIKE '%rosiglitazone%'
        OR LOWER(e.medication) LIKE '%sitagliptin%'
        OR LOWER(e.medication) LIKE '%linagliptin%'
        OR LOWER(e.medication) LIKE '%saxagliptin%'
        OR LOWER(e.medication) LIKE '%empagliflozin%'
        OR LOWER(e.medication) LIKE '%dapagliflozin%'
        OR LOWER(e.medication) LIKE '%canagliflozin%'
        OR LOWER(e.medication) LIKE '%ertugliflozin%'
        OR LOWER(e.medication) LIKE '%repaglinide%'
        OR LOWER(e.medication) LIKE '%nateglinide%'
        OR LOWER(e.medication) LIKE '%acarbose%'
        OR LOWER(e.medication) LIKE '%miglitol%'
      )
  )
),
insulin_final AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.emar` e
    WHERE e.subject_id = c.subject_id
      AND e.hadm_id = c.hadm_id
      AND e.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR)
      AND e.charttime <= c.dischtime
      AND LOWER(e.medication) LIKE '%insulin%'
  )
),
oral_final AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.emar` e
    WHERE e.subject_id = c.subject_id
      AND e.hadm_id = c.hadm_id
      AND e.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR)
      AND e.charttime <= c.dischtime
      AND (
        LOWER(e.medication) LIKE '%metformin%'
        OR LOWER(e.medication) LIKE '%glipizide%'
        OR LOWER(e.medication) LIKE '%glyburide%'
        OR LOWER(e.medication) LIKE '%glimepiride%'
        OR LOWER(e.medication) LIKE '%pioglitazone%'
        OR LOWER(e.medication) LIKE '%rosiglitazone%'
        OR LOWER(e.medication) LIKE '%sitagliptin%'
        OR LOWER(e.medication) LIKE '%linagliptin%'
        OR LOWER(e.medication) LIKE '%saxagliptin%'
        OR LOWER(e.medication) LIKE '%empagliflozin%'
        OR LOWER(e.medication) LIKE '%dapagliflozin%'
        OR LOWER(e.medication) LIKE '%canagliflozin%'
        OR LOWER(e.medication) LIKE '%ertugliflozin%'
        OR LOWER(e.medication) LIKE '%repaglinide%'
        OR LOWER(e.medication) LIKE '%nateglinide%'
        OR LOWER(e.medication) LIKE '%acarbose%'
        OR LOWER(e.medication) LIKE '%miglitol%'
      )
  )
),
total_cohort AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_admissions
  FROM cohort
)
SELECT
  'First 48 hours' AS period,
  ROUND(100.0 * (SELECT COUNT(DISTINCT hadm_id) FROM insulin_first) / tc.total_admissions, 2) AS pct_insulin,
  ROUND(100.0 * (SELECT COUNT(DISTINCT hadm_id) FROM oral_first) / tc.total_admissions, 2) AS pct_oral
FROM total_cohort tc
UNION ALL
SELECT
  'Final 24 hours' AS period,
  ROUND(100.0 * (SELECT COUNT(DISTINCT hadm_id) FROM insulin_final) / tc.total_admissions, 2) AS pct_insulin,
  ROUND(100.0 * (SELECT COUNT(DISTINCT hadm_id) FROM oral_final) / tc.total_admissions, 2) AS pct_oral
FROM total_cohort tc
ORDER BY period;
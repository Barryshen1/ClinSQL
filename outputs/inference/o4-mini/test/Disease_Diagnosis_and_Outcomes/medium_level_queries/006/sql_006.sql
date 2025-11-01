WITH
-- Step 1 & 2: Identify sepsis admissions in male patients aged 64–74, excluding septic shock
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- ICD-9 sepsis codes
          (d.icd_version = 9 AND d.icd_code LIKE '038.%')
          OR
          -- ICD-10 sepsis codes
          (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^(A40|A41)'))
        )
    )
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.hadm_id = a.hadm_id
        AND (
          -- ICD-9 septic shock
          (d2.icd_version = 9 AND d2.icd_code = '785.52')
          OR
          -- ICD-10 septic shock
          (d2.icd_version = 10 AND d2.icd_code = 'R65.21')
        )
    )
),
-- Step 5: Flag CKD and diabetes per admission
flags AS (
  SELECT
    c.hadm_id,
    -- CKD ICD-9 585.*, ICD-10 N18.*
    MAX(IF(
      (d.icd_version = 9 AND d.icd_code LIKE '585.%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'N18.%'),
      1, 0
    )) AS ckd_flag,
    -- Diabetes ICD-9 250.*, ICD-10 E10.*, E11.*
    MAX(IF(
      (d.icd_version = 9 AND d.icd_code LIKE '250.%')
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10.%' OR d.icd_code LIKE 'E11.%')),
      1, 0
    )) AS diabetes_flag
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON c.hadm_id = d.hadm_id
  GROUP BY
    c.hadm_id
),
-- Step 4: Assign quartiles based on LOS
quartiles AS (
  SELECT
    c.*,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM
    cohort c
)
-- Step 6: Aggregate outcomes by quartile
SELECT
  q.los_quartile AS quartile,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(q.hospital_expire_flag) / COUNT(*), 1) AS mortality_rate_pct,
  ROUND(100.0 * SUM(f.ckd_flag) / COUNT(*), 1)    AS ckd_prevalence_pct,
  ROUND(100.0 * SUM(f.diabetes_flag) / COUNT(*), 1) AS diabetes_prevalence_pct
FROM
  quartiles q
  LEFT JOIN flags f
    ON q.hadm_id = f.hadm_id
GROUP BY
  los_quartile
ORDER BY
  los_quartile;
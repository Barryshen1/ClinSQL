WITH
-- Step 1: Identify men age 75-85
base_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
),

-- Step 2: Sepsis admissions (excluding septic shock)
sepsis_admissions AS (
  SELECT DISTINCT
    bc.subject_id,
    bc.hadm_id,
    bc.admittime,
    bc.dischtime,
    bc.hospital_expire_flag,
    bc.anchor_age,
    bc.gender
  FROM
    base_cohort bc
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON bc.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      -- ICD-10 sepsis
      (d.icd_version = 10 AND (
        REGEXP_CONTAINS(d.icd_code, r'^A40') OR
        REGEXP_CONTAINS(d.icd_code, r'^A41')
      ))
      OR
      -- ICD-9 sepsis
      (d.icd_version = 9 AND (
        REGEXP_CONTAINS(d.icd_code, r'^99591') OR
        REGEXP_CONTAINS(d.icd_code, r'^99592') OR
        REGEXP_CONTAINS(d.icd_code, r'^038')
      ))
    )
    -- Exclude septic shock
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      WHERE dx.hadm_id = bc.hadm_id
        AND (
          -- ICD-10 septic shock
          (dx.icd_version = 10 AND REGEXP_CONTAINS(dx.icd_code, r'^R6521'))
          OR
          -- ICD-9 septic shock
          (dx.icd_version = 9 AND REGEXP_CONTAINS(dx.icd_code, r'^78552'))
        )
    )
),

-- Step 3: Comorbidity flags
comorbidity_flags AS (
  SELECT
    sa.subject_id,
    sa.hadm_id,
    sa.admittime,
    sa.dischtime,
    sa.hospital_expire_flag,
    sa.anchor_age,
    sa.gender,
    -- CKD
    MAX(
      CASE
        WHEN (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^N18'))
          OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^585'))
        THEN 1 ELSE 0
      END
    ) AS has_ckd,
    -- Diabetes
    MAX(
      CASE
        WHEN (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E1[0-4]'))
          OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250'))
        THEN 1 ELSE 0
      END
    ) AS has_diabetes,
    -- AFib
    MAX(
      CASE
        WHEN (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I48'))
          OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^42731'))
        THEN 1 ELSE 0
      END
    ) AS has_afib,
    -- Hypertension
    MAX(
      CASE
        WHEN (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I1[0-5]'))
          OR (d.icd_version = 9 AND (
            REGEXP_CONTAINS(d.icd_code, r'^401') OR
            REGEXP_CONTAINS(d.icd_code, r'^402') OR
            REGEXP_CONTAINS(d.icd_code, r'^403') OR
            REGEXP_CONTAINS(d.icd_code, r'^404') OR
            REGEXP_CONTAINS(d.icd_code, r'^405')
          ))
        THEN 1 ELSE 0
      END
    ) AS has_htn
  FROM
    sepsis_admissions sa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON sa.hadm_id = d.hadm_id
  GROUP BY
    sa.subject_id, sa.hadm_id, sa.admittime, sa.dischtime, sa.hospital_expire_flag, sa.anchor_age, sa.gender
),

-- Step 4: LOS stratification
final_cohort AS (
  SELECT
    *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) <= 5 THEN '<=5'
      ELSE '>5'
    END AS los_group
  FROM
    comorbidity_flags
  WHERE
    admittime IS NOT NULL AND dischtime IS NOT NULL
)

-- Step 5: Aggregate
SELECT
  los_group,
  has_ckd,
  has_diabetes,
  has_afib,
  has_htn,
  COUNT(*) AS admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_percent
FROM
  final_cohort
GROUP BY
  los_group,
  has_ckd,
  has_diabetes,
  has_afib,
  has_htn
ORDER BY
  los_group,
  has_ckd DESC,
  has_diabetes DESC,
  has_afib DESC,
  has_htn DESC;
WITH cohort AS (
  -- Step 1: Identify admissions for females 39-49 with HF
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND (
      -- Heart failure ICD-10: I50.x; ICD-9: 428.x
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50'))
      OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
    )
),
comorbidities AS (
  -- Step 2: For each admission, flag CKD and diabetes, and count other comorbidities
  SELECT
    c.subject_id,
    c.hadm_id,
    c.los_days,
    c.hospital_expire_flag,
    c.anchor_age,
    c.gender,
    -- CKD flag
    MAX(
      CASE
        WHEN (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^N18'))
          OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^585'))
        THEN 1 ELSE 0
      END
    ) AS has_ckd,
    -- Diabetes flag
    MAX(
      CASE
        WHEN (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E1[0134]'))
          OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250'))
        THEN 1 ELSE 0
      END
    ) AS has_diabetes,
    -- Comorbidity count (excluding HF, CKD, diabetes)
    COUNT(DISTINCT
      CASE
        WHEN NOT (
          -- Exclude HF
          (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50'))
          OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
          -- Exclude CKD
          OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^N18'))
          OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^585'))
          -- Exclude diabetes
          OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E1[0134]'))
          OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250'))
        )
        THEN d.icd_code
        ELSE NULL
      END
    ) AS comorbidity_count
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON c.hadm_id = d.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id, c.los_days, c.hospital_expire_flag, c.anchor_age, c.gender
),
tertiles AS (
  -- Step 3: Assign comorbidity tertiles using NTILE(3)
  SELECT
    *,
    NTILE(3) OVER (ORDER BY comorbidity_count) AS tertile_num
  FROM
    comorbidities
),
final AS (
  -- Step 4: Label tertiles and LOS groups
  SELECT
    hadm_id,
    subject_id,
    los_days,
    hospital_expire_flag,
    anchor_age,
    gender,
    has_ckd,
    has_diabetes,
    comorbidity_count,
    CASE
      WHEN tertile_num = 1 THEN 'Low'
      WHEN tertile_num = 2 THEN 'Med'
      WHEN tertile_num = 3 THEN 'High'
    END AS comorbidity_tertile,
    CASE
      WHEN los_days <= 5 THEN '≤5'
      WHEN los_days > 5 THEN '>5'
      ELSE NULL
    END AS los_group
  FROM
    tertiles
  WHERE
    los_days IS NOT NULL
)
-- Step 5: Aggregate by LOS group and comorbidity tertile
SELECT
  los_group,
  comorbidity_tertile,
  COUNT(*) AS N,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS in_hospital_mortality_percent,
  ROUND(100 * SUM(has_ckd) / COUNT(*), 1) AS ckd_prevalence_percent,
  ROUND(100 * SUM(has_diabetes) / COUNT(*), 1) AS diabetes_prevalence_percent
FROM
  final
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group,
  comorbidity_tertile
ORDER BY
  los_group,
  comorbidity_tertile;
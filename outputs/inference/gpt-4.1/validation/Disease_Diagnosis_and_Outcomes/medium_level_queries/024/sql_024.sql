WITH female_49_59 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
),

sepsis_admissions AS (
  -- Find admissions with sepsis but NOT septic shock
  SELECT
    f.*
  FROM
    female_49_59 f
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON f.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      -- Sepsis ICD-10
      (d.icd_version = 10 AND (
        REGEXP_CONTAINS(d.icd_code, r'^A41') OR
        (d.icd_code = 'R65.2' AND d.icd_code != 'R65.21')
      ))
      OR
      -- Sepsis ICD-9
      (d.icd_version = 9 AND (
        d.icd_code IN ('99591', '99592')
      ))
    )
    -- Exclude septic shock
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      WHERE dx.hadm_id = f.hadm_id
        AND (
          (dx.icd_version = 10 AND dx.icd_code = 'R65.21')
          OR (dx.icd_version = 9 AND dx.icd_code = '78552')
        )
    )
),

ckd_flags AS (
  -- Admissions with CKD diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^N18'))
    OR (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^585'))
),

diabetes_flags AS (
  -- Admissions with diabetes diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 10 AND (REGEXP_CONTAINS(icd_code, r'^E10') OR REGEXP_CONTAINS(icd_code, r'^E11') OR REGEXP_CONTAINS(icd_code, r'^E13')))
    OR (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250'))
),

icu_day1 AS (
  -- For each admission, was there an ICU stay in first 24h?
  SELECT
    s.hadm_id,
    MIN(i.intime) AS first_icu_intime,
    MIN(TIMESTAMP_DIFF(i.intime, s.admittime, HOUR)) AS hours_to_icu
  FROM
    sepsis_admissions s
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON s.hadm_id = i.hadm_id
  GROUP BY s.hadm_id, s.admittime
),

final_cohort AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.admittime,
    s.dischtime,
    s.deathtime,
    s.hospital_expire_flag,
    s.anchor_age,
    -- LOS in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(s.dischtime, s.admittime, HOUR), 24) AS los_days,
    -- ICU day-1 flag
    CASE
      WHEN id1.first_icu_intime IS NOT NULL AND id1.hours_to_icu <= 24 THEN 'ICU Day-1'
      ELSE 'Non-ICU Day-1'
    END AS icu_day1_status,
    -- CKD flag
    CASE WHEN ckd.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ckd,
    -- Diabetes flag
    CASE WHEN dia.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_diabetes
  FROM
    sepsis_admissions s
    LEFT JOIN icu_day1 id1 ON s.hadm_id = id1.hadm_id
    LEFT JOIN ckd_flags ckd ON s.hadm_id = ckd.hadm_id
    LEFT JOIN diabetes_flags dia ON s.hadm_id = dia.hadm_id
)

SELECT
  CASE WHEN los_days <= 5 THEN '<=5 days' ELSE '>5 days' END AS los_group,
  icu_day1_status,
  COUNT(*) AS N,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS mortality_percent,
  ROUND(SUM(has_ckd) * 100.0 / COUNT(*), 1) AS ckd_percent,
  ROUND(SUM(has_diabetes) * 100.0 / COUNT(*), 1) AS diabetes_percent
FROM
  final_cohort
GROUP BY
  los_group, icu_day1_status
ORDER BY
  los_group, icu_day1_status;
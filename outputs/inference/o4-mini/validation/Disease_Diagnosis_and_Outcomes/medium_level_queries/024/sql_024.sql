WITH diag_flags AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%sepsis%' THEN 1 ELSE 0 END)       AS has_sepsis,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%septic shock%' THEN 1 ELSE 0 END) AS has_septic_shock,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%chronic kidney disease%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes mellitus%' THEN 1 ELSE 0 END)   AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    -- restrict to ICD descriptions of interest
    LOWER(dd.long_title) LIKE '%sepsis%'
    OR LOWER(dd.long_title) LIKE '%septic shock%'
    OR LOWER(dd.long_title) LIKE '%chronic kidney disease%'
    OR LOWER(dd.long_title) LIKE '%diabetes mellitus%'
  GROUP BY
    d.subject_id,
    d.hadm_id
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    df.has_sepsis,
    df.has_septic_shock,
    df.has_ckd,
    df.has_diabetes,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    LEFT JOIN diag_flags df
      ON a.subject_id = df.subject_id
      AND a.hadm_id = df.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND df.has_sepsis = 1
    AND df.has_septic_shock = 0
),
cohort_icu AS (
  SELECT
    c.*,
    CASE
      WHEN i.stay_id IS NOT NULL
       AND i.intime <= TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
      THEN TRUE
      ELSE FALSE
    END AS icu_day1
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON c.hadm_id = i.hadm_id
)
SELECT
  CASE WHEN los_days <= 5 THEN '≤5' ELSE '>5' END AS los_category,
  IF(icu_day1, 'ICU Day 1', 'Non-ICU Day 1') AS icu_day1_status,
  COUNT(*) AS N,
  100 * AVG(hospital_expire_flag)                    AS mortality_pct,
  100 * AVG(IF(has_ckd = 1, 1, 0))                   AS ckd_prevalence_pct,
  100 * AVG(IF(has_diabetes = 1, 1, 0))              AS diabetes_prevalence_pct
FROM
  cohort_icu
GROUP BY
  los_category,
  icu_day1_status
ORDER BY
  los_category,
  icu_day1_status;
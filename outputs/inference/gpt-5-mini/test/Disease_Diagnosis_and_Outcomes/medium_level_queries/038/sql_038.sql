WITH diag_flags AS (
  -- For each admission (hadm_id) compute flags for HF, CKD, and diabetes based on diagnosis descriptions
  SELECT
    di.hadm_id,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS has_hf,
    MAX(CASE
          WHEN LOWER(d.long_title) LIKE '%chronic kidney%' THEN 1
          WHEN LOWER(d.long_title) LIKE '%ckd%' THEN 1
          WHEN LOWER(d.long_title) LIKE '%kidney failure%' THEN 1
          WHEN LOWER(d.long_title) LIKE '%renal failure%' THEN 1
          ELSE 0
        END) AS has_ckd,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_dm
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code
      AND di.icd_version = d.icd_version
  GROUP BY
    di.hadm_id
),

cohort AS (
  -- Admissions for female patients age 80-90 that have heart failure (per diag_flags)
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    df.has_hf,
    df.has_ckd,
    df.has_dm,
    -- compute hospital LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- ICU flag if any icustay exists for this hadm_id
    CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN diag_flags df
      ON a.hadm_id = df.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON a.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND df.has_hf = 1
    -- require discharge time to compute LOS
    AND a.dischtime IS NOT NULL
)

SELECT
  icu_flag,
  CASE WHEN los_days < 8 THEN '<8 days' ELSE '>=8 days' END AS los_group,
  COUNT(*) AS n_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_inhospital_deaths,
  ROUND(100 * SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)), 1) AS pct_inhospital_mortality,
  SUM(has_ckd) AS n_with_ckd,
  ROUND(100 * SAFE_DIVIDE(SUM(has_ckd), COUNT(*)), 1) AS pct_ckd,
  SUM(has_dm) AS n_with_diabetes,
  ROUND(100 * SAFE_DIVIDE(SUM(has_dm), COUNT(*)), 1) AS pct_diabetes
FROM
  cohort
GROUP BY
  icu_flag,
  los_group
ORDER BY
  icu_flag DESC, -- show ICU first
  los_group;
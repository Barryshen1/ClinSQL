WITH hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- LOS in whole days
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days_raw,
    -- LOS group as requested (ignore LOS < 1 day)
    CASE
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 4 AND 7 THEN '4-7'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) >= 8 THEN '>=8'
      ELSE NULL
    END AS los_group,
    -- ICU on day 1?
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.subject_id = a.subject_id
          AND i.hadm_id = a.hadm_id
          AND i.intime < TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
          AND i.outtime > a.admittime
      ) THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_day1_status,
    -- CKD flag for admission
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
        WHERE di.hadm_id = a.hadm_id
          AND (LOWER(dd.long_title) LIKE '%kidney%' OR LOWER(dd.long_title) LIKE '%neph%')
      ) THEN 1 ELSE 0
    END AS has_ckd,
    -- Diabetes flag for admission
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
        WHERE di.hadm_id = a.hadm_id
          AND (LOWER(dd.long_title) LIKE '%diabetes%' OR LOWER(dd.long_title) LIKE '%diab%')
      ) THEN 1 ELSE 0
    END AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    -- Only HF admissions
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (LOWER(dd.long_title) LIKE '%heart failure%' OR LOWER(dd.long_title) LIKE '%congestive heart failure%')
    )
)

SELECT
  icu_day1_status,
  los_group,
  COUNT(*) AS n_admissions,
  -- median LOS (approximate)
  APPROX_QUANTILES(los_days_raw, 2)[OFFSET(1)] AS median_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS in_hospital_mortality_pct,
  ROUND(100.0 * SUM(has_ckd) / COUNT(*), 2) AS ckd_prevalence_pct,
  ROUND(100.0 * SUM(has_diabetes) / COUNT(*), 2) AS diabetes_prevalence_pct
FROM hf_admissions
WHERE los_group IS NOT NULL
GROUP BY icu_day1_status, los_group
ORDER BY icu_day1_status, los_group;
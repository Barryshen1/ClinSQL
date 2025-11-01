WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 5 THEN '<=5'
      ELSE '>5'
    END AS los_group,
    -- day-1 ICU: any icustay for this hadm_id starting within 24 hours of admission
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE icu.hadm_id = a.hadm_id
        AND icu.intime >= a.admittime
        AND TIMESTAMP_DIFF(icu.intime, a.admittime, HOUR) < 24
    ) AS day1_icu_flag,
    -- CKD flag: any diagnosis long_title indicating chronic kidney disease / ESRD
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        USING (icd_code, icd_version)
      WHERE d.hadm_id = a.hadm_id
        AND (
          LOWER(dd.long_title) LIKE '%chronic kidney%'
          OR LOWER(dd.long_title) LIKE '%chronic renal%'
          OR LOWER(dd.long_title) LIKE '%end stage renal%'
        )
    ) AS ckd_flag,
    -- Diabetes flag: any diagnosis long_title containing 'diabetes'
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        USING (icd_code, icd_version)
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    ) AS diabetes_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.dischtime IS NOT NULL
    -- must have sepsis (but not septic shock)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        USING (icd_code, icd_version)
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%sepsis%'
        AND LOWER(dd.long_title) NOT LIKE '%septic shock%'
    )
    -- exclude any admission that has a septic shock diagnosis
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        USING (icd_code, icd_version)
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%septic shock%'
    )
)

SELECT
  los_group,
  CASE WHEN day1_icu_flag THEN 'Day-1 ICU' ELSE 'Non-ICU day1' END AS day1_icu,
  COUNT(*) AS N,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_pct,
  ROUND(100.0 * SUM(CASE WHEN ckd_flag THEN 1 ELSE 0 END) / COUNT(*), 2) AS ckd_pct,
  ROUND(100.0 * SUM(CASE WHEN diabetes_flag THEN 1 ELSE 0 END) / COUNT(*), 2) AS diabetes_pct
FROM cohort
GROUP BY los_group, day1_icu_flag
ORDER BY los_group, day1_icu;
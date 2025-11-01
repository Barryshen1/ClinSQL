WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN '≤7'
      ELSE '>7'
    END AS los_cat,
    -- Determine if any ICU stay begins within 24h of admission
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE icu.hadm_id = a.hadm_id
          AND icu.intime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
      ) THEN 'yes'
      ELSE 'no'
    END AS icu_day1
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  -- Male, age 67–77
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    -- Acute decompensated heart failure diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON dd.icd_code = d.icd_code
       AND dd.icd_version = d.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%acute%'
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),
comorbid AS (
  SELECT
    c.hadm_id,
    -- CKD indicator
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%chronic kidney disease%' THEN 1 ELSE 0 END) AS ckd_flag,
    -- Diabetes indicator
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS dm_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON d.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = d.icd_code
   AND dd.icd_version = d.icd_version
  GROUP BY c.hadm_id
)
SELECT
  c.los_cat,
  c.icu_day1,
  COUNT(1) AS n_admissions,
  100.0 * SUM(c.hospital_expire_flag) / COUNT(1) AS pct_inhospital_mortality,
  100.0 * SUM(co.ckd_flag)           / COUNT(1) AS pct_ckd,
  100.0 * SUM(co.dm_flag)            / COUNT(1) AS pct_diabetes
FROM cohort c
JOIN comorbid co
  ON co.hadm_id = c.hadm_id
GROUP BY
  c.los_cat,
  c.icu_day1
ORDER BY
  c.los_cat,
  c.icu_day1;
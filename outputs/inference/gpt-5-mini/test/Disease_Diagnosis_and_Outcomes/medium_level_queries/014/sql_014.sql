WITH hf_admissions AS (
  -- Admissions that are male, age 77-87, and have a principal diagnosis of heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days,
    CASE
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_cat,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE icu.hadm_id = a.hadm_id
          AND TIMESTAMP_DIFF(icu.intime, a.admittime, HOUR) >= 0
          AND TIMESTAMP_DIFF(icu.intime, a.admittime, HOUR) < 24
      ) THEN 'ICU'
      ELSE 'Non-ICU'
    END AS day1_icu
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1   -- principal diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND LOWER(COALESCE(dicd.long_title, '')) LIKE '%heart failure%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

cohort_with_flags AS (
  -- Add CKD and diabetes flags per admission by searching all diagnoses for that hadm_id
  SELECT
    h.*,
    -- CKD: look for phrases commonly used in diagnosis descriptions for chronic kidney disease / ESRD
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON dx.icd_code = dd.icd_code AND dx.icd_version = dd.icd_version
      WHERE dx.hadm_id = h.hadm_id
        AND (
          LOWER(COALESCE(dd.long_title, '')) LIKE '%chronic kidney%'
          OR LOWER(COALESCE(dd.long_title, '')) LIKE '%chronic renal%'
          OR LOWER(COALESCE(dd.long_title, '')) LIKE '%end stage renal%'
          OR LOWER(COALESCE(dd.long_title, '')) LIKE '%end-stage renal%'
        )
    ) AS has_ckd,
    -- Diabetes
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON dx.icd_code = dd.icd_code AND dx.icd_version = dd.icd_version
      WHERE dx.hadm_id = h.hadm_id
        AND LOWER(COALESCE(dd.long_title, '')) LIKE '%diabetes%'
    ) AS has_diabetes
  FROM hf_admissions h
)

SELECT
  day1_icu AS day1_icu_status,
  los_cat AS los_category,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS in_hospital_mortality_pct,
  -- median LOS (days) using approximate quantiles (50th percentile)
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  ROUND(100.0 * SUM(CASE WHEN has_ckd THEN 1 ELSE 0 END) / COUNT(*), 1) AS ckd_prevalence_pct,
  ROUND(100.0 * SUM(CASE WHEN has_diabetes THEN 1 ELSE 0 END) / COUNT(*), 1) AS diabetes_prevalence_pct
FROM cohort_with_flags
GROUP BY day1_icu, los_cat
ORDER BY
  -- put ICU first, then Non-ICU; within that order by LOS category 1-3,4-7,>=8
  CASE WHEN day1_icu = 'ICU' THEN 0 ELSE 1 END,
  CASE los_cat WHEN '1-3' THEN 1 WHEN '4-7' THEN 2 ELSE 3 END;
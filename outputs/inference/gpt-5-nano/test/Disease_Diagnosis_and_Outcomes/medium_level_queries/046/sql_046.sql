WITH hf_admissions AS (
  -- Select admissions for males 72-82 with HF and valid discharge time
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CAST(a.hospital_expire_flag AS INT64) AS hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE (p.gender = 'M' OR p.gender = 'Male')
    AND p.anchor_age BETWEEN 72 AND 82
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),
comorbidity AS (
  -- Count non-HF comorbidities per hadm_id
  SELECT di.hadm_id, COUNT(DISTINCT di.icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) NOT LIKE '%heart failure%'
  GROUP BY di.hadm_id
)
SELECT
  CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
  CASE
     WHEN f.los_days <= 3 THEN '≤3'
     WHEN f.los_days <= 6 THEN '4-6'
     WHEN f.los_days <= 10 THEN '7-10'
     ELSE '>10'
  END AS los_bucket,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(CAST(f.hospital_expire_flag AS INT64)) / COUNT(*), 2) AS in_hospital_mortality_pct,
  APPROX_MEDIAN(f.los_days) AS median_los_days,
  AVG(COALESCE(c.comorbidity_count, 0)) AS avg_comorbidity_count
FROM hf_admissions AS f
LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  ON f.subject_id = icu.subject_id AND f.hadm_id = icu.hadm_id
LEFT JOIN comorbidity AS c
  ON f.hadm_id = c.hadm_id
GROUP BY icu_status, los_bucket
ORDER BY icu_status, los_bucket;
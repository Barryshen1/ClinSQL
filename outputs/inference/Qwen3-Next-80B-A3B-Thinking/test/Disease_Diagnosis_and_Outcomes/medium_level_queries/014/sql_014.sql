WITH cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
    ) THEN 1 ELSE 0 END AS icu_flag,
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND (d.icd_code LIKE '585%' OR d.icd_code LIKE '586%'))
          OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%')
        )
    ) THEN 1 ELSE 0 END AS ckd_flag,
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 10 AND d.icd_code BETWEEN 'E10' AND 'E14')
        )
    ) THEN 1 ELSE 0 END AS diabetes_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 77 AND 87
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_hf
      WHERE d_hf.hadm_id = a.hadm_id
        AND (
          (d_hf.icd_version = 9 AND d_hf.icd_code LIKE '428%')
          OR (d_hf.icd_version = 10 AND d_hf.icd_code LIKE 'I50%')
        )
    )
)
SELECT
  icu_flag,
  CASE
    WHEN los <= 3 THEN '1-3 days'
    WHEN los <= 7 THEN '4-7 days'
    ELSE '>=8 days'
  END AS los_category,
  SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_los,
  SUM(ckd_flag) * 100.0 / COUNT(*) AS ckd_prevalence,
  SUM(diabetes_flag) * 100.0 / COUNT(*) AS diabetes_prevalence
FROM cohort
GROUP BY icu_flag, los_category
ORDER BY icu_flag, los_category;
WITH cohort AS (
  SELECT
    a.admittime,
    a.deathtime,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_aki
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di_aki
        ON d_aki.icd_code = di_aki.icd_code AND d_aki.icd_version = di_aki.icd_version
      WHERE d_aki.hadm_id = a.hadm_id
        AND (di_aki.long_title LIKE '%acute kidney injury%' OR di_aki.long_title LIKE '%acute renal failure%')
    ) AS has_aki,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_ards
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di_ards
        ON d_ards.icd_code = di_ards.icd_code AND d_ards.icd_version = di_ards.icd_version
      WHERE d_ards.hadm_id = a.hadm_id
        AND (di_ards.long_title LIKE '%acute respiratory distress syndrome%' OR di_ards.long_title LIKE '%ARDS%')
    ) AS has_ards
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND di.long_title LIKE '%myocardial infarction%'
    )
)
SELECT
  AVG(CASE WHEN deathtime IS NOT NULL AND deathtime <= admittime + INTERVAL 30 DAY THEN 1 ELSE 0 END) AS thirty_day_mortality_rate,
  AVG(has_aki) AS aki_rate,
  AVG(has_ards) AS ards_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CASE WHEN deathtime IS NOT NULL THEN TIMESTAMP_DIFF(deathtime, admittime, DAY) END) AS median_survival_days
FROM cohort;
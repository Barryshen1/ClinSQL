WITH
  ami_hadms AS (
    -- Identify hospital admissions with a diagnosis of Acute Myocardial Infarction (AMI)
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes for AMI start with 410
      (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '410')
      -- ICD-10 codes for AMI start with I21
      OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I21')
  ),
  first_troponin AS (
    -- Find the first Troponin T measurement for each admission and filter by value
    SELECT
      hadm_id,
      valuenum AS first_troponin_t_value
    FROM (
      SELECT
        hadm_id,
        valuenum,
        -- Rank troponin results chronologically for each admission
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
      FROM `physionet-data.mimiciv_3_1_hosp.labevents`
      WHERE
        itemid = 51003 -- Troponin T
        AND valuenum IS NOT NULL
    ) AS ranked_trop
    WHERE
      rn = 1 -- Select only the first measurement
      AND valuenum > 0.01 -- Ensure the first measurement is > 0.01
  )
-- Final cohort assembly and aggregation
SELECT
  COUNT(DISTINCT p.subject_id) AS patient_count,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  ROUND(AVG(p.anchor_age), 1) AS mean_age,
  ROUND(AVG(DATETIME_DIFF(a.dischtime, a.admittime, DAY)), 1) AS mean_los_days,
  ROUND(MIN(trop.first_troponin_t_value), 2) AS min_first_troponin_t,
  ROUND(MAX(trop.first_troponin_t_value), 2) AS max_first_troponin_t,
  ROUND(AVG(trop.first_troponin_t_value), 2) AS mean_first_troponin_t,
  ROUND(STDDEV(trop.first_troponin_t_value), 2) AS stddev_first_troponin_t,
  ROUND(AVG(a.hospital_expire_flag) * 100, 2) AS in_hospital_mortality_percent
FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  ON p.subject_id = a.subject_id
JOIN ami_hadms AS ami
  ON a.hadm_id = ami.hadm_id
JOIN first_troponin AS trop
  ON a.hadm_id = trop.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 52 AND 62;
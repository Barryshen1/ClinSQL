WITH sepsis_hadm AS (
  -- distinct admissions with a diagnosis whose description contains 'sepsis'
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
),
cohort AS (
  -- ICU stays for female patients age 58-68 on admissions flagged as sepsis
  SELECT DISTINCT icu.stay_id,
         icu.los,
         icu.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND icu.hadm_id IN (SELECT hadm_id FROM sepsis_hadm)
    AND icu.los IS NOT NULL
),
ordered AS (
  -- order the cohort by LOS to pick median exactly
  SELECT stay_id,
         los,
         subject_id,
         ROW_NUMBER() OVER (ORDER BY los, stay_id) AS rn
  FROM cohort
),
counts AS (
  SELECT COUNT(*) AS n
  FROM cohort
)
SELECT
  CASE
    WHEN n = 0 THEN NULL
    WHEN MOD(n, 2) = 1
      THEN (SELECT los FROM ordered WHERE rn = (n + 1) / 2)
    ELSE (
      (SELECT los FROM ordered WHERE rn = n / 2)
      + (SELECT los FROM ordered WHERE rn = n / 2 + 1)
    ) / 2.0
  END AS median_icu_los_days,
  n AS icu_stay_count,
  (SELECT COUNT(DISTINCT subject_id) FROM cohort) AS distinct_patient_count
FROM counts;
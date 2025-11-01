WITH aki_icd_codes AS (
  -- List AKI ICD codes (ICD-9: 584.x, ICD-10: N17.x)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '584%')
    OR (icd_version = 10 AND icd_code LIKE 'N17%')
),
aki_admissions AS (
  -- Admissions with AKI diagnosis
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN aki_icd_codes a
    ON d.icd_code = a.icd_code AND d.icd_version = a.icd_version
),
target_patients AS (
  -- Female patients aged 48-58
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 48 AND 58
),
target_icu_stays AS (
  -- ICU stays for target patients and AKI admissions
  SELECT icu.stay_id, icu.subject_id, icu.hadm_id, icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN aki_admissions aki
    ON icu.subject_id = aki.subject_id AND icu.hadm_id = aki.hadm_id
  INNER JOIN target_patients tp
    ON icu.subject_id = tp.subject_id
  WHERE icu.los IS NOT NULL
)
SELECT
  percentile_cont(los, 0.25) OVER() AS los_25th_percentile_days
FROM target_icu_stays
LIMIT 1;
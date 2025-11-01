WITH aki_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10 AND long_title LIKE '%Acute kidney injury%'
),
aki_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON p.subject_id = di.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 48 AND 58
  AND di.icd_code IN (SELECT icd_code FROM aki_icd_codes) AND di.icd_version = 10
),
icu_stays AS (
  SELECT i.stay_id, i.subject_id, i.intime, i.outtime,
         DATETIME_DIFF(i.outtime, i.intime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN aki_patients ap ON i.subject_id = ap.subject_id
)
SELECT APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS percentile_25th_los
FROM icu_stays;
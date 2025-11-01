WITH aki_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '584%')
     OR (icd_version = 10 AND UPPER(icd_code) LIKE 'N17%')
)
SELECT
  APPROX_QUANTILES(s.los, 100)[OFFSET(25)] AS icu_los_p25_days,
  COUNT(*) AS num_icustays
FROM `physionet-data.mimiciv_3_1_icu.icustays` s
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON s.subject_id = p.subject_id
JOIN aki_hadm a
  ON s.hadm_id = a.hadm_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 48 AND 58
  AND s.los IS NOT NULL
  AND s.los >= 0;
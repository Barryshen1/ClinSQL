WITH stroke_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON d.icd_code = dic.icd_code
   AND d.icd_version = dic.icd_version
  WHERE LOWER(dic.long_title) LIKE '%stroke%'
)

SELECT
  COUNT(*) AS icu_encounters,
  APPROX_QUANTILES(icu.los, 2)[OFFSET(1)] AS median_icu_los_days
FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON icu.subject_id = p.subject_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 35 AND 45
  AND icu.hadm_id IN (SELECT hadm_id FROM stroke_hadm)
  AND icu.los IS NOT NULL;
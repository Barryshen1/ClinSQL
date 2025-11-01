SELECT
  APPROX_QUANTILES(icustay.los, 100)[OFFSET(49)] AS median_icu_los_hours
FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icustay
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON icustay.subject_id = pat.subject_id
LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON icustay.subject_id = diag.subject_id
  AND icustay.hadm_id = diag.hadm_id
LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dcode
  ON diag.icd_code = dcode.icd_code
  AND diag.icd_version = dcode.icd_version
WHERE LOWER(pat.gender) = 'f'
  AND pat.anchor_age BETWEEN 35 AND 45
  AND LOWER(dcode.long_title) LIKE '%stroke%';
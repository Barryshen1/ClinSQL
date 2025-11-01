SELECT
  PERCENTILE_CONT(icu.los, 0.5) OVER() AS median_icu_los
FROM
  physionet-data.mimiciv_3_1_hosp.patients pat
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions adm
  ON pat.subject_id = adm.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
  ON adm.hadm_id = diag.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_diag
  ON diag.icd_code = d_diag.icd_code
  AND diag.icd_version = d_diag.icd_version
JOIN
  physionet-data.mimiciv_3_1_icu.icustays icu
  ON adm.hadm_id = icu.hadm_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 58 AND 68
  AND LOWER(d_diag.long_title) LIKE '%sepsis%'
LIMIT 1;
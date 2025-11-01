SELECT
  APPROX_QUANTILES(icu.los, 100)[OFFSET(25)] AS los_25th_percentile
FROM
  physionet-data.mimiciv_3_1_icu.icustays icu
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions adm
  ON icu.hadm_id = adm.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.patients pat
  ON adm.subject_id = pat.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
  ON adm.hadm_id = diag.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_diag
  ON diag.icd_code = d_diag.icd_code
  AND diag.icd_version = d_diag.icd_version
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 48 AND 58
  AND (
    (diag.icd_version = 9 AND diag.icd_code = '5849')
    OR
    (diag.icd_version = 10 AND diag.icd_code = 'N179')
  );
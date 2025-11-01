SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_icu_los
FROM (
  SELECT DISTINCT
    i.los
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND (
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I60%') OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I61%') OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
    )
    AND (
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
    ) BETWEEN 35 AND 45
);
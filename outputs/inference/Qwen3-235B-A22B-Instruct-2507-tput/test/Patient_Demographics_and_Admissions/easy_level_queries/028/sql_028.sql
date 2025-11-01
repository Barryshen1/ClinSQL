SELECT
  STDDEV(icu.los) AS std_icu_los
FROM
  physionet-data.mimiciv_3_1_hosp.patients p
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions adm
  ON p.subject_id = adm.subject_id
JOIN
  physionet-data.mimiciv_3_1_icu.icustays icu
  ON adm.hadm_id = icu.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
  ON adm.hadm_id = diag.hadm_id
WHERE
  p.gender = 'M'
  AND diag.icd_version = 10
  AND (
    diag.icd_code LIKE 'A40%' OR
    diag.icd_code LIKE 'A41%' OR
    diag.icd_code LIKE 'R65.2%'
  )
  AND (
    EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age)
  ) BETWEEN 90 AND 100;
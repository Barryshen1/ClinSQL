WITH cap_patients AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id
    AND adm.hadm_id = diag.hadm_id
  -- primary diagnosis only
    AND diag.seq_num = 1
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 83 AND 93
    AND UPPER(adm.admission_type) != 'ELECTIVE'
    AND (
      (diag.icd_version = 9 AND (
           diag.icd_code LIKE '481%' OR
           diag.icd_code LIKE '482%' OR
           diag.icd_code LIKE '483%' OR
           diag.icd_code LIKE '485%' OR
           diag.icd_code LIKE '486%' OR
           diag.icd_code LIKE '4870%'
      ))
      OR
      (diag.icd_version = 10 AND (
           UPPER(diag.icd_code) LIKE 'J13%' OR
           UPPER(diag.icd_code) LIKE 'J14%' OR
           UPPER(diag.icd_code) LIKE 'J15%' OR
           UPPER(diag.icd_code) LIKE 'J16%' OR
           UPPER(diag.icd_code) LIKE 'J18%'
      ))
    )
)
SELECT
  PERCENTILE_CONT(los_days, 0.5) OVER() AS median_los_days
FROM cap_patients;
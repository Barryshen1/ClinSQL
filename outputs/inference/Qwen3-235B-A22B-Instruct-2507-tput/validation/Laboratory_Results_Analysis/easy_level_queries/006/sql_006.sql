WITH patient_cohort AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON p.subject_id = di.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.anchor_age = 50
    AND p.gender = 'F'
    AND LOWER(d.long_title) LIKE '%chronic obstructive%'
),
admission_sodium_nadir AS (
  SELECT le.hadm_id, MIN(le.valuenum) AS nadir_sodium
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl ON le.itemid = dl.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON le.hadm_id = a.hadm_id
  INNER JOIN patient_cohort pc ON a.subject_id = pc.subject_id
  WHERE LOWER(dl.label) = 'sodium'
    AND LOWER(dl.fluid) = 'blood'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= a.admittime
    AND le.charttime <= a.dischtime
  GROUP BY le.hadm_id
)
SELECT STDDEV(nadir_sodium) AS sodium_nadir_std_dev
FROM admission_sodium_nadir;
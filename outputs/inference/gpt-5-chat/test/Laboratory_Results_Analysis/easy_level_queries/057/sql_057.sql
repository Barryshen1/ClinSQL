WITH pneumonia_male_61 AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON diag.icd_code = dd.icd_code
    AND diag.icd_version = dd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age = 61
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
creatinine_labs AS (
  SELECT le.subject_id, le.hadm_id, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  JOIN pneumonia_male_61 coh
    ON le.hadm_id = coh.hadm_id
  WHERE di.fluid = 'Blood'
    AND LOWER(di.label) LIKE '%creatinine%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND le.charttime BETWEEN coh.admittime AND coh.dischtime
),
nadir_per_stay AS (
  SELECT hadm_id, MIN(valuenum) AS nadir_creatinine
  FROM creatinine_labs
  GROUP BY hadm_id
)
SELECT
  APPROX_QUANTILES(nadir_creatinine, 4)[1] AS q1,
  APPROX_QUANTILES(nadir_creatinine, 4)[3] AS q3,
  APPROX_QUANTILES(nadir_creatinine, 4)[3] - APPROX_QUANTILES(nadir_creatinine, 4)[1] AS iqr
FROM nadir_per_stay;
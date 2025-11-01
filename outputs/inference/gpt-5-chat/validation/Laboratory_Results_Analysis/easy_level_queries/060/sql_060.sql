WITH male_pneumonia_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiag
    ON diag.icd_code = ddiag.icd_code
    AND diag.icd_version = ddiag.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age = 67
    AND LOWER(ddiag.long_title) LIKE '%pneumonia%'
),
glucose_first24h AS (
  SELECT
    mpa.subject_id,
    mpa.hadm_id,
    AVG(le.valuenum) AS mean_glucose
  FROM male_pneumonia_admissions mpa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON mpa.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE le.valuenum IS NOT NULL
    AND LOWER(dl.label) LIKE '%glucose%'
    AND LOWER(dl.fluid) IN ('blood', 'serum')
    AND le.charttime >= mpa.admittime
    AND le.charttime < DATETIME_ADD(mpa.admittime, INTERVAL 24 HOUR)
  GROUP BY mpa.subject_id, mpa.hadm_id
)
SELECT
  PERCENTILE_CONT(mean_glucose, 0.75) OVER() AS p75_mean_glucose
FROM glucose_first24h;
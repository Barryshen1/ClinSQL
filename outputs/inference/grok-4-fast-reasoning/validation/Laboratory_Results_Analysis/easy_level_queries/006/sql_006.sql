WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age = 50
    AND (LOWER(dd.long_title) LIKE '%copd%'
         OR LOWER(dd.long_title) LIKE '%chronic obstructive pulmonary disease%')
),
nadirs AS (
  SELECT
    c.hadm_id,
    MIN(le.valuenum) AS nadir_na
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
  WHERE le.itemid = 220645
    AND le.valuenum IS NOT NULL
    AND le.charttime >= c.admittime
    AND le.charttime <= c.dischtime
  GROUP BY c.hadm_id
  HAVING nadir_na IS NOT NULL
)
SELECT
  STDDEV(nadir_na) AS stddev_nadir_sodium
FROM nadirs;
WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND (
      (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
      OR (di.icd_version = 9 AND di.icd_code LIKE '428%')
    )
),
nadirs AS (
  SELECT
    c.hadm_id,
    MIN(le.valuenum) AS nadir_hgb
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
  WHERE le.itemid = 51221
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'g/dL'
    AND le.charttime >= c.admittime
    AND le.charttime <= c.dischtime
  GROUP BY c.hadm_id
  HAVING nadir_hgb IS NOT NULL
)
SELECT
  APPROX_QUANTILES(nadir_hgb, 100)[OFFSET(75)] AS p75_nadir_hgb
FROM nadirs;
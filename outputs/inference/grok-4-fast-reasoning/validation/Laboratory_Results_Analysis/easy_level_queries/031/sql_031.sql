WITH qualifying_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id
    AND a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND a.dischtime IS NOT NULL
),
potassium_measurements AS (
  SELECT
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN qualifying_admissions qa
    ON l.subject_id = qa.subject_id
    AND l.hadm_id = qa.hadm_id
  WHERE l.itemid = 50971
    AND l.valuenum IS NOT NULL
    AND DATE(l.charttime) = DATE(qa.dischtime)
)
SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75_serum_potassium
FROM potassium_measurements;
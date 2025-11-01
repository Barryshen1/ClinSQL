WITH cohort AS (
  SELECT DISTINCT
    ie.stay_id,
    ie.hadm_id,
    ie.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
    AND ie.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND adm.admission_type = 'EMERGENCY'
),
sbp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
    AND LOWER(category) LIKE '%blood pressure%'
),
max_sbp_per_stay AS (
  SELECT
    c.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  INNER JOIN sbp_items si
    ON ce.itemid = si.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY c.stay_id
)
SELECT
  PERCENTILE_CONT(max_sbp, 0.75) OVER () AS p75_max_sbp
FROM max_sbp_per_stay
LIMIT 1;
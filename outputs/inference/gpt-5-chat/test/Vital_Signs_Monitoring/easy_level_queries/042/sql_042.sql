WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 63 AND 73
),
rr_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'respiratory rate'
    AND linksto = 'chartevents'
),
max_rr_per_stay AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    MAX(ce.valuenum) AS max_rr_stay
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN cohort c ON ce.subject_id = c.subject_id
  JOIN rr_itemids rri ON ce.itemid = rri.itemid
  WHERE ce.valuenum IS NOT NULL
  GROUP BY ce.subject_id, ce.stay_id
),
max_rr_per_patient AS (
  SELECT
    subject_id,
    MAX(max_rr_stay) AS max_rr_patient
  FROM max_rr_per_stay
  GROUP BY subject_id
)
SELECT
  STDDEV_SAMP(max_rr_patient) AS sd_max_rr
FROM max_rr_per_patient;
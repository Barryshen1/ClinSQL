WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 77 AND 87
),
icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN cohort c ON i.subject_id = c.subject_id
),
first_gcs AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    MIN(ce.charttime) AS first_gcs_time
  FROM icu_stays icu
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id
    AND icu.stay_id = ce.stay_id
  WHERE ce.itemid = 223901 -- GCS Total
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
),
gcs_values AS (
  SELECT
    fg.subject_id,
    fg.hadm_id,
    fg.stay_id,
    ce.valuenum AS first_gcs_total
  FROM first_gcs fg
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fg.subject_id = ce.subject_id
    AND fg.stay_id = ce.stay_id
    AND ce.itemid = 223901
    AND ce.charttime = fg.first_gcs_time
    AND ce.valuenum IS NOT NULL
)
SELECT
  AVG(first_gcs_total) AS avg_first_gcs_total
FROM gcs_values;
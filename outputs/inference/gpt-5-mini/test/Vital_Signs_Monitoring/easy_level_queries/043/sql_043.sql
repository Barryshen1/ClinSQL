WITH gcs_items AS (
  -- identify itemids that likely correspond to GCS total/score
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE (LOWER(label) LIKE '%gcs%' OR LOWER(label) LIKE '%glasgow%' OR LOWER(abbreviation) LIKE '%gcs%')
    AND (LOWER(label) LIKE '%total%' OR LOWER(label) LIKE '%score%' OR LOWER(label) LIKE '%total score%')
),

gcs_events AS (
  -- chartevents restricted to identified GCS total items with numeric values
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN gcs_items gi USING(itemid)
  WHERE ce.valuenum IS NOT NULL
),

earliest_gcs_per_stay AS (
  -- earliest GCS charttime per ICU stay within the first 24 hours after ICU intime
  SELECT
    ge.stay_id,
    ge.subject_id,
    ge.hadm_id,
    MIN(ge.charttime) AS first_gcs_time
  FROM gcs_events ge
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` s
    ON ge.stay_id = s.stay_id
  WHERE ge.charttime >= s.intime
    AND ge.charttime <= TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  GROUP BY ge.stay_id, ge.subject_id, ge.hadm_id
),

first_gcs_value AS (
  -- get the numeric GCS value that corresponds to the earliest time per stay
  SELECT
    eg.stay_id,
    eg.subject_id,
    eg.hadm_id,
    ge.valuenum AS first_gcs,
    eg.first_gcs_time
  FROM earliest_gcs_per_stay eg
  JOIN gcs_events ge
    ON ge.stay_id = eg.stay_id
   AND ge.charttime = eg.first_gcs_time
  -- ensure plausible GCS totals only
  WHERE ge.valuenum BETWEEN 3 AND 15
)

SELECT
  ROUND(AVG(fg.first_gcs), 2) AS avg_first_gcs_total,
  COUNT(DISTINCT fg.stay_id) AS n_icustays,
  COUNT(DISTINCT fg.subject_id) AS n_subjects
FROM first_gcs_value fg
JOIN `physionet-data.mimiciv_3_1_icu.icustays` s
  ON fg.stay_id = s.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON fg.subject_id = p.subject_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 77 AND 87;
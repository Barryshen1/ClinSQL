WITH patient_icu_age AS (
  SELECT
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age AS age_at_icu,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age) BETWEEN 81 AND 91
),
systolic_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(category) = 'vital signs'
    AND (LOWER(label) LIKE '%systolic%' OR LOWER(label) LIKE '%sbp%')
),
sbp_measurements AS (
  SELECT
    pi.stay_id,
    ce.valuenum
  FROM patient_icu_age pi
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON pi.stay_id = ce.stay_id
  INNER JOIN systolic_items si
    ON ce.itemid = si.itemid
  WHERE ce.charttime >= pi.intime
    AND ce.charttime < TIMESTAMP_ADD(pi.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
),
avg_sbp_per_stay AS (
  SELECT
    stay_id,
    AVG(valuenum) AS avg_sbp
  FROM sbp_measurements
  GROUP BY stay_id
)
SELECT
  IF(COUNT(*) = 0, NULL, COUNT(CASE WHEN avg_sbp <= 150 THEN 1 END) * 100.0 / COUNT(*)) AS percentile_of_150
FROM avg_sbp_per_stay;
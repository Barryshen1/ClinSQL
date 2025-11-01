WITH cohort_avg_sbp AS (
  SELECT
    ie.stay_id,
    AVG(ch.valuenum) AS avg_sbp
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ch
    ON ie.stay_id = ch.stay_id
    AND ch.itemid = 220045  -- Systolic Blood Pressure
    AND ch.charttime >= ie.intime
    AND ch.charttime < DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
  WHERE
    p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM ie.intime) - p.anchor_year BETWEEN 38 AND 48
  GROUP BY
    ie.stay_id
)
SELECT
  (COUNT(CASE WHEN avg_sbp <= 120 THEN 1 END) * 100.0) / COUNT(*) AS percentile
FROM
  cohort_avg_sbp;
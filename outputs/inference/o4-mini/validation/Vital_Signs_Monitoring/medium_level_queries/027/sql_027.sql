WITH female_elderly_icustays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
),

hr_events AS (
  SELECT
    ce.stay_id,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%heart rate%'
    AND ce.valuenum IS NOT NULL
    -- Optionally filter implausible heart rates:
    AND ce.valuenum BETWEEN 30 AND 250
),

avg_hr_per_stay AS (
  SELECT
    fe.stay_id,
    AVG(h.valuenum) AS avg_hr
  FROM
    female_elderly_icustays AS fe
    JOIN hr_events AS h
      ON fe.stay_id = h.stay_id
  GROUP BY
    fe.stay_id
)

SELECT
  110 AS query_hr_bpm,
  100.0 * SUM(CASE WHEN avg_hr <= 110 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_of_110
FROM
  avg_hr_per_stay;
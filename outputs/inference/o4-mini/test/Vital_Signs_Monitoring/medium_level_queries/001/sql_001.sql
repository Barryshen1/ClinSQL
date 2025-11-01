WITH female_icustays AS (
  SELECT
    p.subject_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      ON p.subject_id = icu.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
),
sbp_events AS (
  SELECT
    f.subject_id,
    f.stay_id,
    ce.valuenum
  FROM
    female_icustays AS f
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON f.subject_id = ce.subject_id
     AND f.stay_id    = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%systolic%'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN f.intime
                        AND TIMESTAMP_ADD(f.intime, INTERVAL 24 HOUR)
),
avg_sbp_per_stay AS (
  SELECT
    subject_id,
    stay_id,
    AVG(valuenum) AS avg_sbp
  FROM
    sbp_events
  GROUP BY
    subject_id,
    stay_id
),
bucketed AS (
  SELECT
    subject_id,
    stay_id,
    CASE
      WHEN avg_sbp < 140 THEN '<140'
      WHEN avg_sbp BETWEEN 140 AND 159 THEN '140–159'
      ELSE '>=160'
    END AS sbp_bucket
  FROM
    avg_sbp_per_stay
)
SELECT
  sbp_bucket,
  COUNT(DISTINCT subject_id) AS unique_patient_count
FROM
  bucketed
GROUP BY
  sbp_bucket
ORDER BY
  -- preserve logical bucket order
  CASE sbp_bucket
    WHEN '<140'   THEN 1
    WHEN '140–159' THEN 2
    WHEN '>=160'  THEN 3
  END;
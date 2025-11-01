WITH first_rr_per_stay AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    rr.valuenum AS first_rr
  FROM (
    SELECT
      ce.subject_id,
      ce.hadm_id,
      ce.stay_id,
      ce.valuenum,
      ce.charttime,
      ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN
      `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    -- filter to respiratory rate measurements
    WHERE
      LOWER(di.label) LIKE '%respiratory rate%'
      AND ce.valuenum IS NOT NULL
  ) rr
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON rr.subject_id = icu.subject_id
   AND rr.hadm_id    = icu.hadm_id
   AND rr.stay_id    = icu.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE
    rr.rn = 1                           -- first measurement per stay
    AND p.gender = 'F'                  -- female
    AND p.anchor_age BETWEEN 51 AND 61  -- age 51–61
)

SELECT
  -- 25th percentile of the first respiratory rate per ICU stay
  APPROX_QUANTILES(first_rr, 100)[OFFSET(25)] AS rr_25th_percentile
FROM
  first_rr_per_stay;
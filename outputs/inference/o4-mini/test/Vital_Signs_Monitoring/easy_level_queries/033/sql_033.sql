WITH female_icudays AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON ic.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
),
hr_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN female_icudays fic
      ON ce.subject_id = fic.subject_id
      AND ce.hadm_id = fic.hadm_id
      AND ce.stay_id = fic.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%heart rate%'
    AND ce.valuenum IS NOT NULL
    -- Compute ICU day and filter for day >= 2
    AND DATE_DIFF(DATE(ce.charttime), DATE(fic.intime), DAY) + 1 >= 2
)
SELECT
  quantiles[OFFSET(1)] AS heart_rate_25th_percentile,
  quantiles[OFFSET(3)] AS heart_rate_75th_percentile
FROM (
  SELECT
    APPROX_QUANTILES(valuenum, 4) AS quantiles
  FROM
    hr_events
);
WITH
  -- 1) Identify female patients age 65-75
  eligible_patients AS (
    SELECT
      subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'F'
      AND anchor_age BETWEEN 65 AND 75
  ),

  -- 2) Get their ICU stays
  eligible_icustays AS (
    SELECT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime,
      TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR) AS intime_plus_24h
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    JOIN
      eligible_patients AS p
    ON
      icu.subject_id = p.subject_id
  ),

  -- 3) Find all systolic BP itemids
  systolic_items AS (
    SELECT
      itemid
    FROM
      `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE
      category = 'Vital Signs'
      AND LOWER(label) LIKE '%systolic%'
  ),

  -- 4) Gather all systolic BP measurements in first 24h
  sysbp_first24 AS (
    SELECT
      e.valuenum AS sbp,
      CASE
        WHEN e.valuenum < 140 THEN '<140'
        WHEN e.valuenum BETWEEN 140 AND 159 THEN '140-159'
        ELSE '>=160'
      END AS sbp_category
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` AS e
    JOIN
      eligible_icustays AS icu
    ON
      e.subject_id = icu.subject_id
      AND e.stay_id    = icu.stay_id
    JOIN
      systolic_items AS si
    ON
      e.itemid = si.itemid
    WHERE
      e.valuenum IS NOT NULL
      AND e.charttime BETWEEN icu.intime AND icu.intime_plus_24h
  )

-- 5) Aggregate by category: compute mean, median, IQR
SELECT
  sbp_category,
  ROUND(mean_sbp, 2) AS mean_sbp,
  quantiles[OFFSET(2)] AS median_sbp,
  quantiles[OFFSET(1)] AS q1_sbp,
  quantiles[OFFSET(3)] AS q3_sbp,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_sbp
FROM (
  SELECT
    sbp_category,
    AVG(sbp) AS mean_sbp,
    APPROX_QUANTILES(sbp, 4) AS quantiles
  FROM
    sysbp_first24
  GROUP BY
    sbp_category
)
ORDER BY
  sbp_category;
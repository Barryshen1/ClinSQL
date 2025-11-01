WITH cohort AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.intime,
    icu.outtime
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 75 AND 85
),
systolic_bp_measurements AS (
  SELECT
    ch.stay_id,
    ch.valuenum
  FROM
    physionet-data.mimiciv_3_1_icu.chartevents ch
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ch.itemid = di.itemid
  JOIN
    cohort co
    ON ch.stay_id = co.stay_id
  WHERE
    LOWER(di.label) = 'systolic blood pressure'
    AND ch.valuenum IS NOT NULL
    AND ch.valuenum BETWEEN 0 AND 300
    AND ch.charttime >= co.intime
    AND ch.charttime <= co.intime + INTERVAL 48 HOUR
),
stay_means AS (
  SELECT
    stay_id,
    AVG(valuenum) AS mean_systolic_bp
  FROM
    systolic_bp_measurements
  GROUP BY
    stay_id
),
percentiles AS (
  SELECT
    APPROX_QUANTILES(mean_systolic_bp, 100) AS quantiles
  FROM
    stay_means
)
SELECT
  (
    SELECT
      CAST(SUM(IF(q <= 140, 1, 0)) AS FLOAT64) / COUNT(*) * 100
    FROM
      UNNEST((SELECT quantiles FROM percentiles)) AS q
  ) AS percentile_of_140;
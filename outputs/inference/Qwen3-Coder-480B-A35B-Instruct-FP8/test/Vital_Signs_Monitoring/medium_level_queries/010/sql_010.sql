WITH cohort_sbp AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM
    physionet-data.mimiciv_3_1_icu.icustays AS icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients AS pat
    ON icu.subject_id = pat.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.chartevents AS ce
    ON icu.stay_id = ce.stay_id
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items AS di
    ON ce.itemid = di.itemid
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 77 AND 87
    AND LOWER(di.label) LIKE '%systolic%'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY
    ce.stay_id
),
percentile_rank AS (
  SELECT
    APPROX_QUANTILES(avg_sbp, 100) AS quantiles
  FROM
    cohort_sbp
)
SELECT
  (
    SELECT
      CAST(SUM(CASE WHEN q <= 160 THEN 1 ELSE 0 END) AS FLOAT64) / COUNT(*) AS percentile
    FROM
      UNNEST((SELECT quantiles FROM percentile_rank)) AS q
  ) * 100 AS percentile_rank_160;
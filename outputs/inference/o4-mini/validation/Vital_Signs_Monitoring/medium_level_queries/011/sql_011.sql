WITH rr_per_stay AS (
  SELECT
    s.stay_id,
    AVG(ce.valuenum) AS avg_rr
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` s
      ON p.subject_id = s.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON ce.subject_id = s.subject_id
     AND ce.stay_id    = s.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND di.label = 'Respiratory Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN s.intime
                       AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
  GROUP BY
    s.stay_id
),
binned AS (
  SELECT
    stay_id,
    avg_rr,
    CASE
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr BETWEEN 12 AND 20 THEN '12-20'
      WHEN avg_rr BETWEEN 21 AND 29 THEN '21-29'
      ELSE '>=30'
    END AS rr_bin
  FROM rr_per_stay
)
SELECT
  rr_bin AS bin,
  COUNT(*) AS n,
  ROUND(AVG(avg_rr), 2) AS mean_avg_rr,
  ROUND(APPROX_QUANTILES(avg_rr, 4)[OFFSET(2)], 2) AS median_avg_rr,
  ROUND(
    APPROX_QUANTILES(avg_rr, 4)[OFFSET(3)]
    - APPROX_QUANTILES(avg_rr, 4)[OFFSET(1)],
    2
  ) AS iqr_avg_rr
FROM
  binned
GROUP BY
  rr_bin
ORDER BY
  CASE rr_bin
    WHEN '<12' THEN 1
    WHEN '12-20' THEN 2
    WHEN '21-29' THEN 3
    WHEN '>=30' THEN 4
  END;
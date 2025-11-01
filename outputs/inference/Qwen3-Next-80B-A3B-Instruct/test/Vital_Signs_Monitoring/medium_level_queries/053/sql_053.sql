WITH sbp_measurements AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS sbp_value,
    ce.charttime,
    i.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON ce.stay_id = i.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND LOWER(di.label) IN (
      'systolic bp',
      'arterial bp systolic',
      'bp systolic',
      'blood pressure systolic',
      'sbp'
    )
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300  -- biologically plausible upper bound
    AND ce.charttime >= i.intime
    AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
),
categorized_sbp AS (
  SELECT
    sbp_value,
    CASE
      WHEN sbp_value < 140 THEN '<140'
      WHEN sbp_value BETWEEN 140 AND 159 THEN '140–159'
      WHEN sbp_value >= 160 THEN '≥160'
    END AS sbp_category
  FROM
    sbp_measurements
)
SELECT
  sbp_category,
  AVG(sbp_value) AS mean_sbp,
  PERCENTILE_CONT(sbp_value, 0.5) AS median_sbp,
  PERCENTILE_CONT(sbp_value, 0.75) - PERCENTILE_CONT(sbp_value, 0.25) AS iqr_sbp
FROM
  categorized_sbp
WHERE
  sbp_category IS NOT NULL
GROUP BY
  sbp_category
ORDER BY
  sbp_category;
WITH heart_rate_per_stay AS (
  SELECT
    i.stay_id,
    AVG(ce.valuenum) AS mean_heart_rate
  FROM
    physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.chartevents ce
    ON i.stay_id = ce.stay_id
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300  -- reasonable physiological range
  GROUP BY
    i.stay_id
)
SELECT
  APPROX_QUANTILES(mean_heart_rate, 1000)[OFFSET(500)] AS median_per_stay_mean_heart_rate
FROM
  heart_rate_per_stay;
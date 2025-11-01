WITH male_arterial_ph AS (
  SELECT
    ce.subject_id,
    MAX(ce.valuenum) AS peak_ph
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND di.label = 'pH, arterial'  -- Known arterial pH in MIMIC-IV
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 6.5 AND 8.0  -- Physiological range, avoid outliers
  GROUP BY
    ce.subject_id
)
SELECT
  APPROX_QUANTILES(peak_ph, 1000)[OFFSET(250)] AS q1,  -- 25th percentile
  APPROX_QUANTILES(peak_ph, 1000)[OFFSET(750)] AS q3,  -- 75th percentile
  APPROX_QUANTILES(peak_ph, 1000)[OFFSET(750)] - APPROX_QUANTILES(peak_ph, 1000)[OFFSET(250)] AS iqr
FROM
  male_arterial_ph;
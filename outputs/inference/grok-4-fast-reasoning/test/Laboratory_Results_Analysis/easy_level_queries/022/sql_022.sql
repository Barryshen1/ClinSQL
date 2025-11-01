WITH arterial_ph AS (
  SELECT
    icu.subject_id,
    ce.valuenum AS ph
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON ce.stay_id = icu.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON icu.subject_id = pat.subject_id
  WHERE
    ce.itemid = 220235
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 6.0
    AND ce.valuenum < 8.0
    AND pat.gender = 'M'
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
),
peaks AS (
  SELECT
    subject_id,
    MAX(ph) AS peak_ph
  FROM arterial_ph
  GROUP BY subject_id
  HAVING peak_ph IS NOT NULL
)
SELECT
  APPROX_QUANTILES(peak_ph, 4)[OFFSET(3)] - APPROX_QUANTILES(peak_ph, 4)[OFFSET(1)] AS iqr_peak_ph
FROM peaks;
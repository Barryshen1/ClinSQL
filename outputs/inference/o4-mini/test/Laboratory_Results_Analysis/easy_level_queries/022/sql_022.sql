WITH abg_ph AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum AS ph_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    di.category = 'Arterial Blood Gas'
    AND LOWER(di.label) LIKE '%ph%'
    AND ce.valuenum IS NOT NULL
),

peak_ph_per_stay AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    MAX(a.ph_value) AS peak_ph
  FROM
    abg_ph a
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.stay_id
),

male_icu_peaks AS (
  SELECT
    pps.*
  FROM
    peak_ph_per_stay pps
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    pps.subject_id = p.subject_id
  -- filter to male ICU patients
  WHERE
    p.gender = 'M'
)

SELECT
  -- Compute approximate quartiles: APPX_QUANTILES returns an array of length = num_buckets+1
  quantiles[OFFSET(1)] AS p25,
  quantiles[OFFSET(3)] AS p75,
  SAFE_CAST(quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS FLOAT64) AS iqr
FROM (
  SELECT
    APPROX_QUANTILES(peak_ph, 4) AS quantiles
  FROM
    male_icu_peaks
);
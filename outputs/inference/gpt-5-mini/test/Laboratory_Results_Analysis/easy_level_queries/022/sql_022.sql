WITH ph_ce AS (
  -- pH measurements charted in the ICU (chartevents + d_items)
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    AND SAFE_CAST(ce.valuenum AS FLOAT64) BETWEEN 6.5 AND 8.0
    AND LOWER(di.label) LIKE '%ph%'
    AND (
      LOWER(di.label) LIKE '%arterial%'
      OR LOWER(di.label) LIKE '%abg%'
      OR LOWER(di.label) LIKE '%blood gas%'
    )
),
ph_lab AS (
  -- pH measurements from hospital lab results that fall within an ICU stay
  SELECT
    le.subject_id,
    le.hadm_id,
    ic.stay_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
    ON le.subject_id = ic.subject_id
   AND le.hadm_id = ic.hadm_id
   AND le.charttime BETWEEN ic.intime AND ic.outtime
  WHERE le.valuenum IS NOT NULL
    AND SAFE_CAST(le.valuenum AS FLOAT64) BETWEEN 6.5 AND 8.0
    AND LOWER(dli.label) LIKE '%ph%'
    AND (
      LOWER(dli.label) LIKE '%arterial%'
      OR LOWER(dli.label) LIKE '%abg%'
      OR LOWER(dli.label) LIKE '%blood gas%'
      OR LOWER(dli.fluid) LIKE '%arterial%'
    )
),
all_ph AS (
  SELECT * FROM ph_ce
  UNION ALL
  SELECT * FROM ph_lab
),
peak_ph_per_stay AS (
  -- peak (maximum) pH per ICU stay
  SELECT
    stay_id,
    subject_id,
    MAX(valuenum) AS peak_ph
  FROM all_ph
  GROUP BY stay_id, subject_id
),
male_peaks AS (
  -- restrict to male patients
  SELECT pps.*
  FROM peak_ph_per_stay pps
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON pps.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
)
-- compute 25th, 75th percentiles and IQR across male ICU stay peak pH values
SELECT
  APPROX_QUANTILES(peak_ph, 100)[OFFSET(25)] AS p25_peak_ph,
  APPROX_QUANTILES(peak_ph, 100)[OFFSET(75)] AS p75_peak_ph,
  APPROX_QUANTILES(peak_ph, 100)[OFFSET(75)] - APPROX_QUANTILES(peak_ph, 100)[OFFSET(25)] AS iqr_peak_ph,
  COUNT(*) AS n_stays
FROM male_peaks;
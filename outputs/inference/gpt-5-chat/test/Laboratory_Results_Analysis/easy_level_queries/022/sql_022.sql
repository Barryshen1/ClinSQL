WITH male_63_icu AS (
  SELECT DISTINCT icu.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age = 63
),
ph_arterial_events AS (
  SELECT ce.subject_id, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN male_63_icu m
    ON ce.subject_id = m.subject_id
  WHERE di.label LIKE '%pH%'
    AND LOWER(di.label) LIKE '%art%'  -- ensure arterial pH
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 6.5 AND 8.0  -- plausible physiological range
),
peak_ph_per_patient AS (
  SELECT
    subject_id,
    MAX(valuenum) AS peak_ph
  FROM ph_arterial_events
  GROUP BY subject_id
)
SELECT
  APPROX_QUANTILES(peak_ph, 4)[OFFSET(3)] - APPROX_QUANTILES(peak_ph, 4)[OFFSET(1)] AS iqr_peak_ph
FROM peak_ph_per_patient;
WITH abg_pH_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE category = 'ABG' AND LOWER(label) LIKE '%ph%'
),
peak_pH_per_stay AS (
  SELECT 
    ce.stay_id,
    MAX(ce.valuenum) AS peak_pH
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN abg_pH_itemids abg ON ce.itemid = abg.itemid
  WHERE ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
)
SELECT
  APPROX_QUANTILES(peak_pH, 4)[OFFSET(1)] AS Q1,
  APPROX_QUANTILES(peak_pH, 4)[OFFSET(3)] AS Q3,
  APPROX_QUANTILES(peak_pH, 4)[OFFSET(3)] - APPROX_QUANTILES(peak_pH, 4)[OFFSET(1)] AS IQR
FROM peak_pH_per_stay pps
JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON pps.stay_id = icu.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON icu.subject_id = pat.subject_id
WHERE pat.gender = 'M' AND pat.anchor_age >= 18;
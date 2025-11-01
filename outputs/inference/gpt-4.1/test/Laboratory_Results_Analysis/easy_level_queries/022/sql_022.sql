WITH abg_ph_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%ph%'
    AND LOWER(category) LIKE '%abg%'
),

-- Step 2: Get peak pH per male ICU stay
peak_ph_per_stay AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    MAX(lab.valuenum) AS peak_ph
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON icu.subject_id = lab.subject_id
    AND icu.hadm_id = lab.hadm_id
    AND lab.valuenum IS NOT NULL
    AND lab.charttime BETWEEN icu.intime AND icu.outtime
  JOIN abg_ph_items
    ON lab.itemid = abg_ph_items.itemid
  WHERE pat.gender = 'M'
  GROUP BY icu.stay_id, icu.subject_id
)

-- Step 3: Calculate IQR of peak pH
SELECT
  APPROX_QUANTILES(peak_ph, 4)[OFFSET(1)] AS p25_peak_ph,
  APPROX_QUANTILES(peak_ph, 4)[OFFSET(3)] AS p75_peak_ph,
  APPROX_QUANTILES(peak_ph, 4)[OFFSET(3)] - APPROX_QUANTILES(peak_ph, 4)[OFFSET(1)] AS iqr_peak_ph
FROM peak_ph_per_stay
WHERE peak_ph IS NOT NULL;
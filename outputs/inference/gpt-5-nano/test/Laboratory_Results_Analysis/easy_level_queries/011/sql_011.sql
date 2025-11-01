WITH potassium_peaks AS (
  SELECT
    icu.stay_id,
    MAX(ce.valuenum) AS peak_potassium
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    -- Identify potassium measurements
    AND LOWER(di.label) LIKE '%potassium%'
    -- Use numeric values for calculation
    AND ce.valuenum IS NOT NULL
  GROUP BY icu.stay_id
)

SELECT STDDEV_SAMP(peak_potassium) AS sd_peak_potassium_mEq_per_L
FROM potassium_peaks;
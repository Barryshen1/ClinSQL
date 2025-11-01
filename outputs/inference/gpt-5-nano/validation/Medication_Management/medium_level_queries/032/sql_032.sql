WITH eligible_stays AS (
  SELECT icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = icu.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON dd.icd_code = di.icd_code
       AND dd.icd_version = di.icd_version
      WHERE di.subject_id = icu.subject_id
        AND di.hadm_id = icu.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd2
        ON dd2.icd_code = di2.icd_code
       AND dd2.icd_version = di2.icd_version
      WHERE di2.subject_id = icu.subject_id
        AND di2.hadm_id = icu.hadm_id
        AND LOWER(dd2.long_title) LIKE '%heart failure%'
    )
),

-- 2) Extract insulin-related events from ICU within the two windows
insulin_events AS (
  SELECT
    ie.stay_id,
    CASE
      WHEN ie.charttime >= icu.intime AND ie.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
        THEN 'First24h'
      WHEN ie.charttime >= TIMESTAMP_SUB(icu.outtime, INTERVAL 12 HOUR) AND ie.charttime <= icu.outtime
        THEN 'Final12h'
      ELSE NULL
    END AS window_label,
    CASE
      WHEN LOWER(di.label) LIKE '%basal%' OR LOWER(di.label) LIKE '%glargine%' OR LOWER(di.label) LIKE '%detemir%'
        THEN 'basal'
      WHEN LOWER(di.label) LIKE '%bolus%' OR LOWER(di.label) LIKE '%regular%' OR LOWER(di.label) LIKE '%lispro%'
           OR LOWER(di.label) LIKE '%aspart%' OR LOWER(di.label) LIKE '%glulisine%'
        THEN 'bolus'
      WHEN LOWER(ie.ordercategorydescription) LIKE '%sliding scale%'
        THEN 'sliding'
      ELSE NULL
    END AS insulin_type
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
  JOIN eligible_stays AS es ON es.stay_id = ie.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu ON ie.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di ON ie.itemid = di.itemid
  WHERE ie.charttime IS NOT NULL
    AND ie.charttime >= icu.intime
    AND ie.charttime <= icu.outtime
),

per_stay_window AS (
  SELECT
    stay_id,
    window_label,
    MAX(CASE WHEN insulin_type = 'basal' THEN 1 ELSE 0 END) AS has_basal,
    MAX(CASE WHEN insulin_type = 'bolus' THEN 1 ELSE 0 END) AS has_bolus,
    MAX(CASE WHEN insulin_type = 'sliding' THEN 1 ELSE 0 END) AS has_sliding
  FROM insulin_events
  WHERE window_label IN ('First24h','Final12h') AND insulin_type IS NOT NULL
  GROUP BY stay_id, window_label
),

-- 4) Map each stay/window to a single regimen
first_rows AS (
  SELECT
    stay_id,
    'First24h' AS window_label2,
    CASE
      WHEN has_basal = 1 AND has_bolus = 1 THEN 'Basal-Bolus'
      WHEN has_basal = 1 AND has_bolus = 0 THEN 'Basal'
      WHEN has_bolus = 1 AND has_basal = 0 THEN 'Bolus'
      WHEN has_sliding = 1 THEN 'Sliding-Scale'
      ELSE NULL
    END AS regimen
  FROM per_stay_window
  WHERE window_label = 'First24h'
),
final_rows AS (
  SELECT
    stay_id,
    'Final12h' AS window_label2,
    CASE
      WHEN has_basal = 1 AND has_bolus = 1 THEN 'Basal-Bolus'
      WHEN has_basal = 1 AND has_bolus = 0 THEN 'Basal'
      WHEN has_bolus = 1 AND has_basal = 0 THEN 'Bolus'
      WHEN has_sliding = 1 THEN 'Sliding-Scale'
      ELSE NULL
    END AS regimen
  FROM per_stay_window
  WHERE window_label = 'Final12h'
),

-- 5) Counts and totals per window
first_counts AS (
  SELECT regimen, COUNT(*) AS n
  FROM first_rows
  WHERE regimen IS NOT NULL
  GROUP BY regimen
),
first_tot AS (
  SELECT SUM(n) AS total FROM first_counts
),
final_counts AS (
  SELECT regimen, COUNT(*) AS n
  FROM final_rows
  WHERE regimen IS NOT NULL
  GROUP BY regimen
),
final_tot AS (
  SELECT SUM(n) AS total FROM final_counts
)

-- 6) Combine into a final table showing prevalences and change
SELECT
  COALESCE(f.regimen, r.regimen) AS regimen,
  IFNULL(100.0 * f.n / ft.total, NULL) AS first24h_pct,
  IFNULL(100.0 * r.n / rt.total, NULL) AS final12h_pct,
  (IFNULL(100.0 * f.n / ft.total, 0) - IFNULL(100.0 * r.n / rt.total, 0)) AS pct_point_change
FROM first_counts f
FULL OUTER JOIN final_counts r ON f.regimen = r.regimen
CROSS JOIN first_tot ft
CROSS JOIN final_tot rt
ORDER BY regimen;
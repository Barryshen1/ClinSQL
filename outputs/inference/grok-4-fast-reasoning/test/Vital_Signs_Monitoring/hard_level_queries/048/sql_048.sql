WITH cohort_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 75 AND 85
),
ventilated_stays AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime, icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN cohort_patients cp ON icu.subject_id = cp.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    WHERE ce.subject_id = icu.subject_id
      AND ce.hadm_id = icu.hadm_id
      AND ce.stay_id = icu.stay_id
      AND ce.itemid IN (720, 223834, 223835, 224009)
      AND ce.charttime BETWEEN icu.intime AND icu.outtime
  )
),
-- HR (tachycardia >100)
hr_real AS (
  SELECT 
    vs.subject_id, vs.hadm_id, vs.stay_id, vs.intime,
    ce.charttime, ce.valuenum AS hr
  FROM ventilated_stays vs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = vs.subject_id
    AND ce.hadm_id = vs.hadm_id
    AND ce.stay_id = vs.stay_id
    AND ce.itemid = 220045
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN vs.intime AND vs.intime + INTERVAL 48 HOUR
),
stays_with_hr AS (
  SELECT DISTINCT subject_id, hadm_id, stay_id, intime
  FROM hr_real
),
hr_augmented AS (
  SELECT subject_id, hadm_id, stay_id, intime, charttime, hr
  FROM hr_real
  UNION ALL
  SELECT subject_id, hadm_id, stay_id, intime, intime AS charttime, CAST(NULL AS FLOAT64) AS hr
  FROM stays_with_hr
),
hr_intervals AS (
  SELECT 
    subject_id, hadm_id, stay_id,
    charttime, hr,
    LEAD(charttime) OVER (PARTITION BY subject_id, hadm_id, stay_id ORDER BY charttime) AS next_charttime,
    intime + INTERVAL 48 HOUR AS end_48
  FROM hr_augmented
),
tach_abnormal AS (
  SELECT 
    subject_id, stay_id,
    SUM(
      CASE 
        WHEN hr > 100 THEN 
          TIMESTAMP_DIFF(COALESCE(next_charttime, end_48), charttime, SECOND) / 3600.0
        ELSE 0 
      END
    ) AS tach_hours
  FROM hr_intervals
  GROUP BY subject_id, stay_id
),
-- MAP (hypotension <65)
map_real AS (
  SELECT 
    vs.subject_id, vs.hadm_id, vs.stay_id, vs.intime,
    ce.charttime, ce.valuenum AS map_val
  FROM ventilated_stays vs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = vs.subject_id
    AND ce.hadm_id = vs.hadm_id
    AND ce.stay_id = vs.stay_id
    AND ce.itemid = 220052
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN vs.intime AND vs.intime + INTERVAL 48 HOUR
),
stays_with_map AS (
  SELECT DISTINCT subject_id, hadm_id, stay_id, intime
  FROM map_real
),
map_augmented AS (
  SELECT subject_id, hadm_id, stay_id, intime, charttime, map_val
  FROM map_real
  UNION ALL
  SELECT subject_id, hadm_id, stay_id, intime, intime AS charttime, CAST(NULL AS FLOAT64) AS map_val
  FROM stays_with_map
),
map_intervals AS (
  SELECT 
    subject_id, hadm_id, stay_id,
    charttime, map_val,
    LEAD(charttime) OVER (PARTITION BY subject_id, hadm_id, stay_id ORDER BY charttime) AS next_charttime,
    intime + INTERVAL 48 HOUR AS end_48
  FROM map_augmented
),
hyp_abnormal AS (
  SELECT 
    subject_id, stay_id,
    SUM(
      CASE 
        WHEN map_val < 65 THEN 
          TIMESTAMP_DIFF(COALESCE(next_charttime, end_48), charttime, SECOND) / 3600.0
        ELSE 0 
      END
    ) AS hyp_hours
  FROM map_intervals
  GROUP BY subject_id, stay_id
),
-- Scores
scores AS (
  SELECT 
    vs.subject_id, vs.stay_id, vs.hadm_id, vs.los,
    COALESCE(ta.tach_hours, 0) AS tach_hours,
    COALESCE(ha.hyp_hours, 0) AS hyp_hours,
    48.0 AS total_hours
  FROM ventilated_stays vs
  LEFT JOIN tach_abnormal ta 
    ON ta.subject_id = vs.subject_id AND ta.stay_id = vs.stay_id
  LEFT JOIN hyp_abnormal ha 
    ON ha.subject_id = vs.subject_id AND ha.stay_id = vs.stay_id
),
scores_with_frac AS (
  SELECT *,
    tach_hours / total_hours AS frac_tach,
    hyp_hours / total_hours AS frac_hyp,
    (tach_hours + hyp_hours) / (2 * total_hours) AS composite_frac
  FROM scores
),
-- Mortality
final_scores AS (
  SELECT 
    s.*,
    COALESCE(a.hospital_expire_flag, 0) AS died
  FROM scores_with_frac s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
),
-- Percentiles
p90 AS (
  SELECT APPROX_QUANTILES(composite_frac, 100)[OFFSET(90)] AS score_p90
  FROM final_scores
),
p75 AS (
  SELECT APPROX_QUANTILES(composite_frac, 100)[OFFSET(75)] AS score_p75
  FROM final_scores
)
-- Output metrics
SELECT 
  '90th percentile of the 48-hour composite instability score (%)' AS metric,
  ROUND(p90.score_p90 * 100, 2) AS value
FROM p90
UNION ALL
SELECT 
  'Average hypotension in top 25% (%)' AS metric,
  ROUND(AVG(fs.frac_hyp) * 100, 2) AS value
FROM final_scores fs
CROSS JOIN p75
WHERE fs.composite_frac >= p75.score_p75
UNION ALL
SELECT 
  'Average tachycardia in top 25% (%)' AS metric,
  ROUND(AVG(fs.frac_tach) * 100, 2) AS value
FROM final_scores fs
CROSS JOIN p75
WHERE fs.composite_frac >= p75.score_p75
UNION ALL
SELECT 
  'Average ICU LOS in top 25% (days)' AS metric,
  ROUND(AVG(fs.los), 2) AS value
FROM final_scores fs
CROSS JOIN p75
WHERE fs.composite_frac >= p75.score_p75
UNION ALL
SELECT 
  'Mortality in top 25% (%)' AS metric,
  ROUND(AVG(fs.died) * 100, 2) AS value
FROM final_scores fs
CROSS JOIN p75
WHERE fs.composite_frac >= p75.score_p75
ORDER BY metric;
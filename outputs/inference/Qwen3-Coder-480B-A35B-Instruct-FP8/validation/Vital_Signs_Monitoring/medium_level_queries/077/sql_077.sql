WITH cohort_stays AS (
  SELECT ie.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 42 AND 52
),
hr_stay_avg AS (
  SELECT ce.stay_id,
         AVG(ce.valuenum) AS avg_hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%heart rate%'
    AND ce.valuenum IS NOT NULL
    AND ce.stay_id IN (SELECT stay_id FROM cohort_stays)
  GROUP BY ce.stay_id
),
percentile_calc AS (
  SELECT avg_hr,
         PERCENT_RANK() OVER (ORDER BY avg_hr) * 100 AS percentile
  FROM hr_stay_avg
)
SELECT 
  COUNT(*) AS cohort_size,
  MAX(CASE WHEN avg_hr = 90 THEN percentile END) AS percentile_of_90_bpm
FROM percentile_calc;
WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 82 AND 92
),
max_map_per_hadm AS (
  SELECT ie.hadm_id, MAX(ce.valuenum) AS max_map
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ie.stay_id = ce.stay_id
  INNER JOIN filtered_patients fp ON ie.subject_id = fp.subject_id
  WHERE ce.itemid = 220052  
  GROUP BY ie.hadm_id
)
SELECT APPROX_QUANTILES(max_map, 100)[OFFSET(50)] AS median_max_map
FROM max_map_per_hadm;
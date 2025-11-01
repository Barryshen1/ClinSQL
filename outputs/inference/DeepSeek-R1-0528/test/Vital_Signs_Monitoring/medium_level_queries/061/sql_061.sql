WITH cohort AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  WHERE 
    pat.gender = 'M'
    AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 38 AND 48
),

map_data AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS map_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid IN (220052, 220181, 225312)  -- MAP itemids
    AND ce.valuenum IS NOT NULL  -- Exclude null/non-numeric values
),

stay_avg AS (
  SELECT 
    c.stay_id,
    AVG(md.map_value) AS avg_map
  FROM cohort c
  INNER JOIN map_data md
    ON c.stay_id = md.stay_id
  GROUP BY c.stay_id
)

SELECT 
  COUNTIF(avg_map <= 60) / COUNT(*) AS percentile_rank
FROM stay_avg;
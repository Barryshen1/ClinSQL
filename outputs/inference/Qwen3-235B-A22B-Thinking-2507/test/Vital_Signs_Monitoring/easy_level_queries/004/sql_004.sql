WITH filtered_stays AS (
  SELECT 
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 37 AND 47
),
temperature_data AS (
  SELECT 
    fs.stay_id,
    CASE 
      WHEN ce.itemid = 223762 THEN (ce.valuenum - 32) * 5/9  -- Convert F to C
      ELSE ce.valuenum  -- Assume Celsius for other temp itemids
    END AS temp_celsius
  FROM filtered_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id
  WHERE ce.itemid IN (223761, 223762)  -- Known temp itemids
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= fs.intime
    AND ce.charttime <= fs.outtime
),
stay_means AS (
  SELECT 
    stay_id,
    AVG(temp_celsius) AS mean_temp
  FROM temperature_data
  GROUP BY stay_id
)
SELECT 
  PERCENTILE_CONT(mean_temp, 0.75) OVER () AS percentile_75
FROM stay_means
LIMIT 1;
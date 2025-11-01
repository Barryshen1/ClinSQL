WITH patient_stay_ages AS (
  SELECT 
    p.subject_id,
    p.gender,
    DATETIME(p.anchor_year, 1, 1, 0, 0, 0) AS anchor_datetime,
    EXTRACT(YEAR FROM DATETIME(ic.intime)) - p.anchor_year + p.anchor_age AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays ic
    ON p.subject_id = ic.subject_id
  WHERE p.gender = 'M'
),
temperature_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%temperature%'
),
stay_avg_temps AS (
  SELECT 
    ic.stay_id,
    AVG(ce.valuenum) AS avg_temperature
  FROM `physionet-data.mimiciv_3_1_icu`.icustays ic
  INNER JOIN patient_stay_ages pa
    ON ic.subject_id = pa.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON ic.stay_id = ce.stay_id
  INNER JOIN temperature_items ti
    ON ce.itemid = ti.itemid
  WHERE 
    pa.age_at_icu BETWEEN 85 AND 95
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ic.intime
    AND ce.charttime <= ic.outtime
  GROUP BY ic.stay_id
)
SELECT 
  COUNT(CASE WHEN avg_temperature <= 36.0 THEN 1 END) * 1.0 / COUNT(*) AS percentile_rank_of_36c
FROM stay_avg_temps;
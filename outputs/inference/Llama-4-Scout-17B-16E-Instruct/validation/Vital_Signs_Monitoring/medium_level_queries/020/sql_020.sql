WITH 
patient_stays AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    ic.stay_id,
    ic.hadm_id,
    ic.intime,
    ic.outtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic 
      ON p.subject_id = ic.subject_id
  WHERE 
    p.gender = 'F' AND 
    p.anchor_age BETWEEN 58 AND 68
),

map_values AS (
  SELECT 
    ps.stay_id,
    ps.hadm_id,
    ps.intime,
    ps.outtime,
    ce.charttime,
    ce.valuenum AS map_value
  FROM 
    patient_stays ps
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON ps.stay_id = ce.stay_id
  WHERE 
    ce.itemid = 220050 
    AND ce.charttime BETWEEN ps.intime AND ps.outtime
),

stay_map_means AS (
  SELECT 
    stay_id,
    hadm_id,
    AVG(map_value) AS mean_map_48hr
  FROM 
    map_values
  GROUP BY 
    stay_id, hadm_id
)

SELECT 
  APPROX_PERCENTILE_CONT(85) WITHIN GROUP (ORDER BY mean_map_48hr) AS percentile_85
FROM 
  stay_map_means;
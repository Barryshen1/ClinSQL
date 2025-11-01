WITH patient_stays AS (
  SELECT 
    icu.stay_id,
    pat.subject_id,
    pat.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat ON icu.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 73 AND 83
    AND (icu.first_careunit IN ('Step-Down Unit', 'Intermediate ICU') 
         OR icu.last_careunit IN ('Step-Down Unit', 'Intermediate ICU'))
),
map_values AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_map
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE 
    itemid = 220052  -- Assuming 220052 is the correct itemid for MAP
  GROUP BY 
    stay_id
)
SELECT 
  AVG(avg_map) AS average_map
FROM 
  patient_stays
INNER JOIN 
  map_values ON patient_stays.stay_id = map_values.stay_id;
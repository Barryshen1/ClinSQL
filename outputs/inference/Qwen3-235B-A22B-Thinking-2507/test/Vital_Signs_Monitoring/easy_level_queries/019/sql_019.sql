WITH filtered_stays AS (
  SELECT 
    icustays.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  WHERE 
    -- Filter for step-down units: check first_careunit (entire stay is in one unit)
    (LOWER(icustays.first_careunit) LIKE '%step%' 
     OR LOWER(icustays.first_careunit) LIKE '%imc%' 
     OR LOWER(icustays.first_careunit) LIKE '%intermediate%')
    AND patients.gender = 'F'
    AND (
      patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year) 
      BETWEEN 73 AND 83
    )
),
stay_map AS (
  SELECT 
    fs.stay_id,
    AVG(ce.valuenum) AS avg_map
  FROM filtered_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (220052, 220179, 225310)
    AND ce.valuenum IS NOT NULL
  GROUP BY fs.stay_id
)
SELECT 
  AVG(avg_map) AS overall_avg_map
FROM stay_map;
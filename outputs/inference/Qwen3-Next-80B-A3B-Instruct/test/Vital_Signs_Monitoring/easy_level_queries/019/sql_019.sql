WITH per_stay_map AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS mean_map_per_stay
  FROM 
    physionet-data.mimiciv_3_1_icu.chartevents ce
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.icustays icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON icu.subject_id = p.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE 
    di.label = 'Mean Arterial Pressure'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND (
      icu.first_careunit IN ('Stepdown Unit (SDU)', 'IMC')
      OR icu.last_careunit IN ('Stepdown Unit (SDU)', 'IMC')
    )
    AND ce.valuenum IS NOT NULL
  GROUP BY 
    ce.stay_id
)
SELECT 
  AVG(mean_map_per_stay) AS average_map_per_stay
FROM 
  per_stay_map;
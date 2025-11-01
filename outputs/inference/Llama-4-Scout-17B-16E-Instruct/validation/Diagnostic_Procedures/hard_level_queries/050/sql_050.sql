WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    i.stay_id,
    i.intime,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    i.los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 76 AND 86
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id 
      AND d.icd_code LIKE '410%'
    )
),

-- Procedures within the first 24 hours of ICU stay and calculate quartiles
quartile_cuts AS (
  SELECT 
    poi.subject_id, 
    poi.hadm_id, 
    poi.stay_id,
    COUNT(DISTINCT p.icd_code) AS procedure_count,
    NTILE(4) OVER (ORDER BY COUNT(DISTINCT p.icd_code)) AS quartile
  FROM 
    patients_of_interest poi
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p 
      ON poi.hadm_id = p.hadm_id
  WHERE 
    p.chartdate BETWEEN poi.intime AND TIMESTAMP_ADD(poi.intime, INTERVAL 1 DAY)
  GROUP BY 
    poi.subject_id, 
    poi.hadm_id, 
    poi.stay_id,
    poi.intime
),

-- Aggregate statistics for each quartile
quartile_stats AS (
  SELECT 
    qc.quartile,
    AVG(qc.procedure_count) AS mean_procedure_count,
    AVG(poi.los) AS mean_icu_los,
    SUM(CASE WHEN poi.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT poi.hadm_id) * 100 AS hospital_mortality
  FROM 
    quartile_cuts qc
  JOIN 
    patients_of_interest poi ON qc.hadm_id = poi.hadm_id
  GROUP BY 
    qc.quartile
)

SELECT 
  quartile,
  mean_procedure_count,
  mean_icu_los,
  hospital_mortality
FROM 
  quartile_stats
ORDER BY 
  quartile;
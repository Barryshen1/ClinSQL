WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    ic.stay_id,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN 
    `physionet-data.mimiciv_3_1_icu`.icustays ic ON a.hadm_id = ic.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.hadm_id IN (
      SELECT 
        hadm_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd 
      WHERE 
        icd_code IN ('415.1', 'I26', 'I26.0', 'I26.1', 'I26.2', 'I26.3', 'I26.4', 'I26.5', 'I26.6', 'I26.8', 'I26.9')
    )
),

-- Procedures in first 72 hours
procedures_first_72_hours AS (
  SELECT 
    poi.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM 
    patients_of_interest poi
  JOIN 
    `physionet-data.mimiciv_3_1_icu`.procedureevents pe ON poi.stay_id = pe.stay_id
  WHERE 
    pe.starttime BETWEEN poi.ic.intime AND TIMESTAMP_ADD(poi.ic.intime, INTERVAL 72 HOUR)
  GROUP BY 
    poi.stay_id
),

-- Calculate quintiles of procedure counts
quintiles AS (
  SELECT 
    stay_id,
    procedure_count,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM 
    procedures_first_72_hours
),

-- Patient outcomes
outcomes AS (
  SELECT 
    poi.hadm_id,
    poi.stay_id,
    a.hospital_expire_flag,
    a.dischtime,
    a.admittime
  FROM 
    patients_of_interest poi
  JOIN 
    `physionet-data.mimiciv_3_1_hosp`.admissions a ON poi.hadm_id = a.hadm_id
)

-- Final aggregation
SELECT 
  q.quintile,
  AVG(q.procedure_count) AS avg_procedure_count,
  AVG(TIMESTAMP_DIFF(o.dischtime, o.admittime, DAY)) AS avg_hospital_los,
  SUM(CASE WHEN o.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(o.hadm_id) * 100 AS mortality_rate
FROM 
  quintiles q
JOIN 
  outcomes o ON q.stay_id = o.stay_id
GROUP BY 
  q.quintile
ORDER BY 
  q.quintile;
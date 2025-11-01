WITH 
patients_of_interest AS (
  SELECT 
    a.subject_id, 
    a.hadm_id,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age = 82 
    AND d.icd_code LIKE '433%'  
),

glucose_levels AS (
  SELECT 
    le.hadm_id, 
    le.charttime,
    le.valuenum AS glucose_level
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` lo 
      ON le.itemid = lo.itemid
  WHERE 
    lo.label = 'Glucose' 
    AND le.valuenum IS NOT NULL
)

SELECT 
  APPROX_QUANTILES(glucose_level, 100)[OFFSET(75)] AS percentile_75_glucose
FROM 
  glucose_levels
WHERE 
  EXISTS (
    SELECT 1
    FROM patients_of_interest poi
    WHERE poi.hadm_id = glucose_levels.hadm_id
      AND glucose_levels.charttime BETWEEN poi.admittime AND poi.admittime + INTERVAL 1 HOUR
  );
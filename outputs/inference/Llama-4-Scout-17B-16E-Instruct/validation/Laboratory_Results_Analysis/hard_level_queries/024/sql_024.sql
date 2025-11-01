WITH 
patients_of_interest AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.admission_type = 'Cardiac Arrest'
),

all_inpatients AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
),

lab_values AS (
  SELECT 
    hadm_id,
    -- Example lab score calculation
    AVG(valuenum) AS lab_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY 
    hadm_id
),

-- Calculate 90th percentile lab instability score
percentile_score AS (
  SELECT 
    APPROX_QUANTILES(lab_score, 0.9)[OFFSET(1)] AS percentile_90
  FROM 
    lab_values
),

critical_patients AS (
  SELECT 
    poi.hadm_id
  FROM 
    patients_of_interest poi
  JOIN 
    lab_values lv
  ON 
    poi.hadm_id = lv.hadm_id
  CROSS JOIN 
    percentile_score ps
  WHERE 
    lv.lab_score >= ps.percentile_90
),

critical_lab_events AS (
  SELECT 
    hadm_id,
    COUNT(*) AS lab_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY 
    hadm_id
),

all_lab_events AS (
  SELECT 
    hadm_id,
    COUNT(*) AS lab_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY 
    hadm_id
)

SELECT 
  COUNT(DISTINCT poi.hadm_id) AS patient_count,
  SUM(CASE WHEN poi.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT poi.hadm_id) AS mortality,
  AVG(DATEDIFF(poi.dischtime, poi.admittime)) AS mean_LOS,
  AVG(cle.lab_count) AS avg_lab_count_critical,
  AVG(ale.lab_count) AS avg_lab_count_all
FROM 
  patients_of_interest poi
  LEFT JOIN critical_lab_events cle ON poi.hadm_id = cle.hadm_id
  LEFT JOIN all_lab_events ale ON poi.hadm_id = ale.hadm_id
  CROSS JOIN percentile_score ps
  JOIN lab_values lv ON poi.hadm_id = lv.hadm_id
WHERE 
  lv.lab_score >= ps.percentile_90;
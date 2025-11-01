WITH 
-- Identify acute pancreatitis patients, male, aged 63-73
target_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age,
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
    d.icd_code LIKE '577.0'  -- Acute pancreatitis ICD-9 code
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
),

-- Calculate lab-instability score (e.g., number of abnormal lab values within 72h)
lab_instability AS (
  SELECT 
    l.hadm_id,
    COUNT(DISTINCT CASE 
      WHEN 
        -- Example condition for abnormal lab value
        l.valueuom = 'mg/dL' AND 
        l.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE label IN ('Creatinine')) 
        AND CAST(l.valuenum AS FLOAT64) > 1.2 
      THEN l.labevent_id 
      ELSE NULL 
    END) AS lab_instability_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN 
    target_patients tp ON l.hadm_id = tp.hadm_id
  WHERE 
    l.charttime BETWEEN 
      TIMESTAMP_ADD(TIMESTAMP_TRUNC(tp.admittime, DAY), INTERVAL 0 DAY) 
      AND TIMESTAMP_ADD(TIMESTAMP_TRUNC(tp.admittime, DAY), INTERVAL 3 DAY)
  GROUP BY 
    l.hadm_id
),

-- Calculate 90th percentile of lab-instability score
p90_score AS (
  SELECT 
    APPROX_QUANTILES(lab_instability_score, 0.9)[OFFSET(1)] AS p90
  FROM 
    lab_instability
),

-- Patient outcomes for those with score >= P90
outcomes AS (
  SELECT 
    tp.hadm_id,
    a.hospital_expire_flag AS mortality,
    TIMESTAMPDIFF(DAY, a.admittime, a.dischtime) AS los
  FROM 
    target_patients tp
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON tp.hadm_id = a.hadm_id
  JOIN 
    lab_instability li ON tp.hadm_id = li.hadm_id
  JOIN 
    p90_score p90 ON li.lab_instability_score >= p90.p90
)

-- Final query
SELECT 
  SUM(mortality) / COUNT(mortality) AS mortality_rate,
  AVG(los) AS mean_los
FROM 
  outcomes;
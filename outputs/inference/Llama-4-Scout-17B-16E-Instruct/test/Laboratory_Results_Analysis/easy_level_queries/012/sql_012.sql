WITH 
  patient_stroke_platelet AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.dischtime,
      le.valuenum AS platelet_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON 
      a.hadm_id = d.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON 
      a.hadm_id = le.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON 
      le.itemid = di.itemid
    WHERE 
      p.anchor_age = 87
      AND p.gender = 'F'
      AND d.icd_code LIKE '430%'  
      AND di.label = 'Platelet Count'
      AND le.charttime BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 1 DAY) AND TIMESTAMP_ADD(a.dischtime, INTERVAL 1 DAY)
  )

-- Calculate 75th percentile of platelet count
SELECT 
  APPROX_QUANTILES(platelet_count, 0.75) AS percentile_75
FROM 
  patient_stroke_platelet;
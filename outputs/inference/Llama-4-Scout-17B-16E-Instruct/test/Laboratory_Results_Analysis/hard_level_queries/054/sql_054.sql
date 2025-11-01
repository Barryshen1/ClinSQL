WITH 
-- Identify AMI patients 
ami_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender,
    a.admittime,
    a.hospital_expire_flag,
    a.dischtime,
    MIN(l.charttime) AS first_lab_time
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` l 
      ON a.hadm_id = l.hadm_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 38 AND 48
    AND d.icd_code LIKE '410%'  -- AMI ICD code
  GROUP BY 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender,
    a.admittime,
    a.hospital_expire_flag,
    a.dischtime
),

-- Calculate lab instability score
lab_instability AS (
  SELECT 
    ap.subject_id, 
    ap.hadm_id, 
    STDDEV(le.valuenum) AS lab_instability_score
  FROM 
    ami_patients ap
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON ap.hadm_id = le.hadm_id
  WHERE 
    le.charttime BETWEEN ap.first_lab_time AND TIMESTAMP_ADD(ap.first_lab_time, INTERVAL 72 HOUR)
  GROUP BY 
    ap.subject_id, 
    ap.hadm_id
),

-- Stratify patients into quartiles
quartiles AS (
  SELECT 
    subject_id, 
    hadm_id, 
    lab_instability_score,
    NTILE(4) OVER (ORDER BY lab_instability_score) AS quartile
  FROM 
    lab_instability
),

-- Calculate LOS and in-hospital mortality for each quartile
los_mortality AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
)

SELECT 
  q.quartile,
  AVG(lm.los) AS avg_los,
  SUM(CASE WHEN lm.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(lm.hadm_id) AS in_hospital_mortality_rate
FROM 
  quartiles q
JOIN 
  los_mortality lm 
    ON q.hadm_id = lm.hadm_id
GROUP BY 
  q.quartile;
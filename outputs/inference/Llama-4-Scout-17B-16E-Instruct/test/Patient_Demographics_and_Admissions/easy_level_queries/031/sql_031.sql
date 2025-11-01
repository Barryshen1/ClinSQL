WITH 
-- Patient demographics and first heart failure admission
patients_of_interest AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    MIN(a.admittime) AS first_hf_admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND d.icd_code IN ('428', '402.01', '402.11', '402.91', '404.01', '404.11', '404.91', '405.01', '405.11', '405.91', 'I50')
  GROUP BY 
    p.subject_id, p.anchor_age, p.gender
),

-- Admissions and readmissions
admissions_with_index AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_index
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

readmissions AS (
  SELECT 
    a1.subject_id,
    a1.hadm_id AS initial_hadm_id,
    a2.hadm_id AS readmission_hadm_id,
    a2.admittime AS readmission_admittime
  FROM 
    admissions_with_index a1
  JOIN 
    admissions_with_index a2 ON a1.subject_id = a2.subject_id
  WHERE 
    a1.admission_index = 1 
    AND a2.admittime BETWEEN TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY) 
    AND TIMESTAMP_ADD(a1.dischtime, INTERVAL 1 DAY)
)

-- Calculate 30-day readmission rate
SELECT 
  AVG(CASE 
        WHEN r.readmission_hadm_id IS NOT NULL THEN 1.0 
        ELSE 0 
      END) AS thirty_day_readmission_rate
FROM 
  patients_of_interest p
  LEFT JOIN readmissions r ON p.subject_id = r.subject_id AND p.first_hf_admittime = r.readmission_admittime;
WITH 
-- Define patients with T2DM and heart failure
t2dm_heart_failure_patients AS (
  SELECT DISTINCT 
    a.subject_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.anchor_age BETWEEN 52 AND 62 
    AND p.gender = 'M'
    AND d.icd_code LIKE '250.0%'  -- T2DM
    AND d.icd_code LIKE '%428%'  -- Heart Failure
),

-- Identify patients who received injectable GLP-1s
glp1_patients AS (
  SELECT 
    e.subject_id,
    e.hadm_id,
    CASE 
      WHEN e.charttime < (a.admittime + INTERVAL 1 DAY) THEN 'first_24h'
      WHEN e.charttime >= (a.admittime + INTERVAL 3 DAY) AND e.charttime < (a.admittime + INTERVAL 5 DAY) THEN 'final_48h'
    END AS period
  FROM 
    `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON e.hadm_id = a.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
      ON e.hadm_id = p.hadm_id AND e.subject_id = p.subject_id
  WHERE 
    p.drug LIKE '%GLP-1%' 
    AND e.charttime IS NOT NULL
),

prevalence AS (
  SELECT 
    period,
    COUNT(DISTINCT subject_id) / (SELECT COUNT(subject_id) FROM t2dm_heart_failure_patients) * 100 AS prevalence
  FROM glp1_patients
  GROUP BY period
)

SELECT 
  p1.period AS first_period,
  p2.period AS second_period,
  p1.prevalence AS first_prevalence,
  p2.prevalence AS second_prevalence,
  p2.prevalence - p1.prevalence AS absolute_change,
  (p2.prevalence - p1.prevalence) / p1.prevalence * 100 AS relative_change
FROM prevalence p1
JOIN prevalence p2 ON p1.period = 'first_24h' AND p2.period = 'final_48h';
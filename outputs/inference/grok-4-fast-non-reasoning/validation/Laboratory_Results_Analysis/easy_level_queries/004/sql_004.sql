WITH similar_patients AS (
  SELECT DISTINCT p.subject_id, MIN(a.admittime) AS first_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'A41%'
  GROUP BY p.subject_id
),
patient_averages AS (
  SELECT 
    sp.subject_id,
    AVG(le.valuenum) AS avg_platelet_first_24h
  FROM similar_patients sp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON sp.subject_id = a.subject_id
    AND a.admittime = sp.first_admittime
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.subject_id = le.subject_id
    AND a.hadm_id = le.hadm_id
  WHERE le.itemid IN (50592, 51265)  -- Platelet count itemids
    AND le.valuenum IS NOT NULL
    AND le.charttime >= a.admittime
    AND le.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
  GROUP BY sp.subject_id
  HAVING AVG(le.valuenum) IS NOT NULL
)
SELECT 
  PERCENTILE_CONT(0.5) OVER() AS median_platelet_count
FROM patient_averages;
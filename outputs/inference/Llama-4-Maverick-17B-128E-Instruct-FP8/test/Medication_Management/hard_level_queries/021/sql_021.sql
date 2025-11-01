WITH 
patient_filter AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 41 AND 51
),
lab_filter AS (
  SELECT DISTINCT le.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  WHERE (dli.label LIKE '%Neutrophil%' AND le.valuenum < 0.5)  
  OR (dli.label LIKE '%Temperature%' AND le.valuenum > 38)  
),
med_count AS (
  SELECT a.hadm_id, COUNT(DISTINCT p.drug) as unique_meds
  FROM patient_filter a
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON a.hadm_id = p.hadm_id
  WHERE p.starttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY a.hadm_id
),
tertiles AS (
  SELECT hadm_id, unique_meds,
         NTILE(3) OVER (ORDER BY unique_meds) as tertile
  FROM med_count
),
metrics AS (
  SELECT 
    t.tertile,
    COUNT(DISTINCT t.hadm_id) as num_patients,
    AVG(TIMESTAMP_DIFF(pf.dischtime, pf.admittime, DAY)) as avg_los,
    SUM(CASE WHEN pf.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT t.hadm_id) * 100 as in_hospital_mortality,
    SUM(CASE 
          WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
            WHERE a2.subject_id = pf.subject_id
            AND a2.admittime > pf.dischtime
            AND TIMESTAMP_DIFF(a2.admittime, pf.dischtime, DAY) <= 30
          ) THEN 1 ELSE 0 END
        ) / COUNT(DISTINCT t.hadm_id) * 100 as thirty_day_readmission
  FROM tertiles t
  JOIN patient_filter pf ON t.hadm_id = pf.hadm_id
  JOIN lab_filter lf ON t.hadm_id = lf.hadm_id
  GROUP BY t.tertile
)
SELECT * FROM metrics;
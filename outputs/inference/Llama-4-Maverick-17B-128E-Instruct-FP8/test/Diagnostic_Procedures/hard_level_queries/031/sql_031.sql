WITH 
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 66 AND 76
),
icu_stays AS (
  SELECT i.stay_id, i.hadm_id, i.subject_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN eligible_patients p ON i.subject_id = p.subject_id
),
procedure_burden AS (
  SELECT i.stay_id, COUNT(*) as num_procedures
  FROM icu_stays i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p ON i.stay_id = p.stay_id
  WHERE p.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  GROUP BY i.stay_id
),
quintiles AS (
  SELECT stay_id, num_procedures, 
         NTILE(5) OVER (ORDER BY num_procedures) as quintile
  FROM procedure_burden
),
additional_data AS (
  SELECT 
    q.stay_id,
    q.quintile,
    q.num_procedures,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS hospital_los,
    a.dischtime,
    a.hadm_id,
    i.subject_id  -- Added subject_id here
  FROM quintiles q
  INNER JOIN icu_stays i ON q.stay_id = i.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
),
stats AS (
  SELECT 
    quintile,
    COUNT(*) as num_icu_stays,
    AVG(num_procedures) as mean_procedures,
    MIN(num_procedures) as min_procedures,
    MAX(num_procedures) as max_procedures,
    AVG(hospital_expire_flag) * 100 as hospital_mortality_pct,
    AVG(hospital_los) as mean_hospital_los
  FROM additional_data
  GROUP BY quintile
),
readmissions AS (
  SELECT 
    a.quintile,
    COUNT(DISTINCT CASE WHEN subsequent_admit.hadm_id IS NOT NULL THEN a.hadm_id ELSE NULL END) as num_readmitted
  FROM additional_data a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` subsequent_admit 
    ON a.subject_id = subsequent_admit.subject_id 
    AND subsequent_admit.admittime BETWEEN a.dischtime AND DATETIME_ADD(a.dischtime, INTERVAL 30 DAY)
    AND a.hadm_id != subsequent_admit.hadm_id
  GROUP BY a.quintile
)
SELECT 
  s.quintile,
  s.num_icu_stays,
  s.mean_procedures,
  s.min_procedures,
  s.max_procedures,
  s.hospital_mortality_pct,
  s.mean_hospital_los,
  r.num_readmitted / s.num_icu_stays * 100 as readmission_pct
FROM stats s
INNER JOIN readmissions r ON s.quintile = r.quintile
ORDER BY s.quintile;
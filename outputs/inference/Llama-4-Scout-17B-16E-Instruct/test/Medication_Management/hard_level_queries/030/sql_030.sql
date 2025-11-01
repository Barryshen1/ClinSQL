WITH 
-- Identify population of interest and calculate medication complexity score
population AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COUNT(DISTINCT ph.medication) AS medication_complexity_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON a.hadm_id = pr.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph ON pr.hadm_id = ph.hadm_id AND pr.starttime = ph.starttime
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 71 AND 81 
    AND di.icd_code = '577.0'
    AND ph.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY 
    a.subject_id, a.hadm_id, p.anchor_age, p.gender, a.admittime, a.dischtime, a.hospital_expire_flag
),
-- Stratify into tertiles
tertiles AS (
  SELECT 
    hadm_id,
    subject_id,
    medication_complexity_score,
    NTILE(3) OVER (ORDER BY medication_complexity_score) AS tertile
  FROM 
    population
),
-- Calculate outcomes
outcomes AS (
  SELECT 
    t.tertile,
    TIMESTAMP_DIFF(p.dischtime, p.admittime, DAY) AS los,
    p.hospital_expire_flag AS in_hospital_mortality,
    -- 30-day readmission flag
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2 
      WHERE a2.subject_id = p.subject_id 
      AND a2.admittime BETWEEN TIMESTAMP_ADD(p.dischtime, INTERVAL 1 DAY) 
      AND TIMESTAMP_ADD(p.dischtime, INTERVAL 30 DAY)
    ) AS thirty_day_readmission
  FROM 
    tertiles t
  JOIN 
    population p ON t.hadm_id = p.hadm_id AND t.subject_id = p.subject_id
)
-- Report outcomes per tertile
SELECT 
  tertile,
  AVG(los) AS avg_los,
  SUM(in_hospital_mortality) / COUNT(*) AS in_hospital_mortality_rate,
  AVG(thirty_day_readmission) AS thirty_day_readmission_rate
FROM 
  outcomes
GROUP BY 
  tertile;
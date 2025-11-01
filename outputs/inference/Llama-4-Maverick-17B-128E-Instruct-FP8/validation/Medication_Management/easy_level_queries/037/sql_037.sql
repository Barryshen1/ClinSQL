WITH patient_data AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age = 55
),
ace_inhibitors AS (
  SELECT p.subject_id, p.starttime, p.stoptime,
         DATETIME_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN patient_data pd ON p.subject_id = pd.subject_id
  WHERE LOWER(drug) LIKE '%ace inhibitor%' OR LOWER(drug) LIKE '%lisinopril%' OR LOWER(drug) LIKE '%enalapril%' 
  OR LOWER(drug) LIKE '%captopril%' OR LOWER(drug) LIKE '%ramipril%' OR LOWER(drug) LIKE '%quinapril%' 
  OR LOWER(drug) LIKE '%perindopril%' OR LOWER(drug) LIKE '%trandolapril%' OR LOWER(drug) LIKE '%fosinopril%'
)
SELECT APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25th
FROM ace_inhibitors;
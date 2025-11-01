WITH 
-- Filter male patients aged 37-47
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 37 AND 47
),

-- First admission for eligible patients
first_admissions AS (
  SELECT subject_id, hadm_id, hospital_expire_flag,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE subject_id IN (SELECT subject_id FROM eligible_patients)
),

-- Identify patients on DAPT during their first admission
dapt_patients AS (
  SELECT fa.subject_id, fa.hadm_id, fa.hospital_expire_flag,
         COUNT(DISTINCT CASE WHEN LOWER(drug) LIKE '%aspirin%' OR LOWER(drug) LIKE '%clopidogrel%' THEN drug END) AS dapt_count
  FROM first_admissions fa
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON fa.hadm_id = p.hadm_id
  WHERE fa.admission_rank = 1 AND (LOWER(drug) LIKE '%aspirin%' OR LOWER(drug) LIKE '%clopidogrel%')
  GROUP BY fa.subject_id, fa.hadm_id, fa.hospital_expire_flag
  HAVING COUNT(DISTINCT CASE WHEN LOWER(drug) LIKE '%aspirin%' OR LOWER(drug) LIKE '%clopidogrel%' THEN drug END) = 2
)

-- Calculate SD of in-hospital mortality
SELECT STDDEV(hospital_expire_flag) AS sd_mortality
FROM dapt_patients;
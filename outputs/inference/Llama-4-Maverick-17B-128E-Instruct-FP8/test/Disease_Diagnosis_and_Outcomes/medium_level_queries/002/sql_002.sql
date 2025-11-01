WITH 
eligible_patients AS (
  SELECT a.hadm_id, p.subject_id, p.anchor_age, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 62 AND 72
),
ami_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Acute myocardial infarction%' AND d.icd_version = 10
),
non_shock_respiratory AS (
  SELECT hadm_id
  FROM eligible_patients
  WHERE hadm_id NOT IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE 'R65.2%' OR icd_code LIKE 'J96%'  
  )
),
los_categorized AS (
  SELECT ep.hadm_id, 
         DATE_DIFF(ep.dischtime, ep.admittime, DAY) AS los,
         CASE WHEN DATE_DIFF(ep.dischtime, ep.admittime, DAY) <= 5 THEN 'LOS <= 5'
              ELSE 'LOS > 5' END AS los_category,
         ep.hospital_expire_flag,
         EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d WHERE d.hadm_id = ep.hadm_id AND d.icd_code LIKE 'N18%') AS has_ckd,
         EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d WHERE d.hadm_id = ep.hadm_id AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%')) AS has_diabetes
  FROM eligible_patients ep
  JOIN ami_patients ap ON ep.hadm_id = ap.hadm_id
  JOIN non_shock_respiratory nsr ON ep.hadm_id = nsr.hadm_id
)
SELECT 
  los_category,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  SUM(CASE WHEN has_ckd THEN 1 ELSE 0 END) AS ckd_count,
  SUM(CASE WHEN has_diabetes THEN 1 ELSE 0 END) AS diabetes_count,
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM los_categorized
GROUP BY los_category;
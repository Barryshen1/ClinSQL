WITH first_admissions AS (
  SELECT subject_id, hadm_id, 
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank,
         hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
cabg_procedures AS (
  SELECT p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Coronary Artery Bypass Graft%' AND p.icd_version = 9 OR d.long_title LIKE '%Coronary artery bypass%' AND p.icd_version = 10
),
eligible_patients AS (
  SELECT p.subject_id, fa.hadm_id, fa.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN first_admissions fa ON p.subject_id = fa.subject_id
  JOIN cabg_procedures cp ON fa.hadm_id = cp.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 35 AND 45 AND fa.admission_rank = 1
)
SELECT COUNT(*) AS total_patients, 
       SUM(hospital_expire_flag) AS in_hospital_deaths,
       SUM(hospital_expire_flag) / COUNT(*) AS in_hospital_mortality
FROM eligible_patients;
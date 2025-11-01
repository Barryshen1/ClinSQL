WITH patient_age AS (
  SELECT p.subject_id, p.gender, 
         EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
         a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
cardiac_procedures AS (
  SELECT p.hadm_id, COUNT(DISTINCT pr.icd_code) AS num_procedures
  FROM patient_age p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  ON p.subject_id = pr.subject_id AND p.hadm_id = pr.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
  ON pr.icd_code = dpr.icd_code AND pr.icd_version = dpr.icd_version
  WHERE p.age_at_admission BETWEEN 76 AND 86
  AND LOWER(dpr.long_title) LIKE '%heart%' OR LOWER(dpr.long_title) LIKE '%cardiac%' 
  GROUP BY p.hadm_id
)
SELECT 
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS q3
FROM cardiac_procedures;
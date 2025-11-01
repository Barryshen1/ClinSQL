WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 57 AND 67
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
    WHERE di.hadm_id = a.hadm_id AND (dicd.long_title LIKE '%Diabetes%' OR di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'E13%' OR di.icd_code LIKE 'E14%')
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
    WHERE di.hadm_id = a.hadm_id AND dicd.long_title LIKE '%Heart failure%'
  )
),
glp1_administration AS (
  SELECT c.subject_id, c.hadm_id,
         MIN(CASE WHEN e.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 3 DAY) THEN 1 ELSE 0 END) AS glp1_first_72h,
         MIN(CASE WHEN e.charttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 1 DAY) AND c.dischtime THEN 1 ELSE 0 END) AS glp1_last_24h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e ON c.hadm_id = e.hadm_id AND (e.medication LIKE '%GLP-1%' OR e.medication LIKE '%Glucagon-like peptide-1%')
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime
)
SELECT 
  SAFE_DIVIDE(COUNT(CASE WHEN glp1_first_72h = 1 THEN subject_id END), COUNT(DISTINCT subject_id)) AS prevalence_first_72h,
  SAFE_DIVIDE(COUNT(CASE WHEN glp1_last_24h = 1 THEN subject_id END), COUNT(DISTINCT subject_id)) AS prevalence_last_24h,
  SAFE_DIVIDE(COUNT(CASE WHEN glp1_first_72h = 0 AND glp1_last_24h = 1 THEN subject_id END), COUNT(DISTINCT subject_id)) AS initiation_rate,
  SAFE_DIVIDE((COUNT(CASE WHEN glp1_last_24h = 1 THEN subject_id END) - COUNT(CASE WHEN glp1_first_72h = 1 THEN subject_id END)), COUNT(DISTINCT subject_id)) AS absolute_change,
  SAFE_DIVIDE((COUNT(CASE WHEN glp1_last_24h = 1 THEN subject_id END) - COUNT(CASE WHEN glp1_first_72h = 1 THEN subject_id END)), COUNT(CASE WHEN glp1_first_72h = 1 THEN subject_id END)) AS relative_change
FROM glp1_administration;
WITH 
-- Define antidiabetic classes
antidiabetic_classes AS (
  SELECT 'insulin' AS class_name, 'insulin' AS medication_pattern UNION ALL
  SELECT 'metformin', 'metformin' UNION ALL
  SELECT 'sulfonylureas', 'sulfonylurea' UNION ALL
  SELECT 'DPP-4', 'DPP-4 inhibitor' UNION ALL
  SELECT 'SGLT2', 'SGLT2 inhibitor' UNION ALL
  SELECT 'GLP-1', 'GLP-1 receptor agonist' UNION ALL
  SELECT 'TZDs', 'thiazolidinedione'
),

-- Filter patients and admissions
patients_filter AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 64 AND 74
  AND a.hadm_id IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN (
      SELECT icd_code
      FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
      WHERE long_title LIKE '%Diabetes%' OR long_title LIKE '%Heart Failure%'
    )
  )
),

-- Identify medication administration
medication_admin AS (
  SELECT pf.subject_id, pf.hadm_id, pf.admittime, pf.dischtime, ac.class_name, pr.starttime
  FROM patients_filter pf
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON pf.hadm_id = pr.hadm_id
  JOIN antidiabetic_classes ac ON LOWER(pr.drug) LIKE CONCAT('%', ac.medication_pattern, '%')
)

-- Calculate initiation percentages
SELECT 
  class_name,
  COUNT(DISTINCT CASE WHEN starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) THEN subject_id END) AS first_12h_initiation,
  COUNT(DISTINCT CASE WHEN starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AND dischtime THEN subject_id END) AS final_48h_initiation,
  COUNT(DISTINCT subject_id) AS total_patients
FROM medication_admin
GROUP BY class_name;
WITH 
-- Filter patients of interest
patients_of_interest AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 86 AND 96
),

-- Identify patients with DM and HF
dm_hf_patients AS (
  SELECT p.subject_id, p.hadm_id
  FROM patients_of_interest p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` i ON d.icd_code = i.icd_code AND d.icd_version = i.icd_version
  WHERE i.long_title IN ('Diabetes mellitus', 'Heart failure')
  GROUP BY p.subject_id, p.hadm_id
  HAVING COUNT(DISTINCT i.long_title) = 2
),

-- Categorize medications and filter by time
treatments AS (
  SELECT 
    d.hadm_id, 
    d.subject_id, 
    a.admittime,
    m.starttime, 
    m.stoptime,
    CASE 
      WHEN m.drug LIKE '%insulin%' THEN 'Insulin'
      WHEN m.drug_type = 'oral' THEN 'Oral Agents'
      ELSE 'Other'
    END AS medication_class
  FROM dm_hf_patients d
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON d.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` m ON d.hadm_id = m.hadm_id
),

-- Early and late treatment periods
early_treatments AS (
  SELECT hadm_id, medication_class,
         COUNT(DISTINCT hadm_id) AS num_patients
  FROM treatments
  WHERE TIMESTAMP_DIFF(TIMESTAMP(m.starttime), TIMESTAMP(admittime), HOUR) <= 12
  GROUP BY hadm_id, medication_class
),

late_treatments AS (
  SELECT hadm_id, medication_class,
         COUNT(DISTINCT hadm_id) AS num_patients
  FROM treatments
  WHERE TIMESTAMP_DIFF(TIMESTAMP_SUB(TIMESTAMP(m.stoptime), INTERVAL 1 DAY * 3), TIMESTAMP(admittime), HOUR) >= 0
  GROUP BY hadm_id, medication_class
)

-- Calculate rates and transitions
SELECT 
  'Early' AS period,
  et.medication_class,
  COUNT(et.hadm_id) AS num_patients,
  COUNT(et.hadm_id) / (SELECT COUNT(*) FROM dm_hf_patients) * 100 AS rate
FROM early_treatments et
GROUP BY et.medication_class

UNION ALL

SELECT 
  'Late' AS period,
  lt.medication_class,
  COUNT(lt.hadm_id) AS num_patients,
  COUNT(lt.hadm_id) / (SELECT COUNT(*) FROM dm_hf_patients) * 100 AS rate
FROM late_treatments lt
GROUP BY lt.medication_class;
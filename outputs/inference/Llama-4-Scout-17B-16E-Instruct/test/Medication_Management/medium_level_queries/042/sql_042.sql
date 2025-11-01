WITH 
  -- Define diabetes and acute HF ICD codes
  diabetes_icd AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE '250%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%'
  ),
  acute_hf_icd AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE '428%' OR icd_code LIKE 'I50%'
  ),
  -- Filter patients of interest
  patients_of_interest AS (
    SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.hadm_id = d1.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.hadm_id = d2.hadm_id
    WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND d1.icd_code IN (SELECT icd_code FROM diabetes_icd)
    AND d2.icd_code IN (SELECT icd_code FROM acute_hf_icd)
  ),
  -- Categorize prescriptions
  prescriptions_categorized AS (
    SELECT 
      poi.hadm_id,
      p.starttime,
      p.stoptime,
      CASE 
        WHEN p.drug LIKE '%insulin%' THEN 'insulin'
        ELSE 'oral'
      END AS drug_category
    FROM patients_of_interest poi
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON poi.hadm_id = p.hadm_id
  )

-- Calculate percentages and counts
SELECT 
  pc.drug_category,
  COUNT(DISTINCT pc.hadm_id) AS patient_count,
  SUM(CASE WHEN pc.starttime BETWEEN poi.admittime AND TIMESTAMP_ADD(poi.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS first_48h_count,
  SUM(CASE WHEN pc.starttime BETWEEN TIMESTAMP_SUB(poi.dischtime, INTERVAL 24 HOUR) AND poi.dischtime THEN 1 ELSE 0 END) AS final_24h_count
FROM prescriptions_categorized pc
JOIN patients_of_interest poi ON pc.hadm_id = poi.hadm_id
GROUP BY pc.drug_category;
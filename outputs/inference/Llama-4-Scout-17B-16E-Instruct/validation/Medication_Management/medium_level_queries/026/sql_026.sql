WITH 
-- Step 1: Identify patients of interest
patients_of_interest AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.hadm_id IN (
      SELECT 
        hadm_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        icd_code IN (
          SELECT 
            icd_code 
          FROM 
            `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
          WHERE 
            long_title IN ('Type 2 diabetes mellitus', 'Heart failure')
        )
      GROUP BY 
        hadm_id 
      HAVING 
        COUNT(DISTINCT icd_code) = 2
    )
),

-- Step 2: Identify medications
medications AS (
  SELECT 
    poi.hadm_id,
    poi.admittime,
    poi.dischtime,
    p.starttime,
    p.drug,
    CASE 
      WHEN p.drug LIKE '%insulin%' THEN 'insulin'
      ELSE 'oral'
    END AS medication_type
  FROM 
    patients_of_interest poi
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
      ON poi.hadm_id = p.hadm_id
  WHERE 
    p.starttime BETWEEN poi.admittime AND poi.dischtime
)

-- Step 3: Calculate percentages
SELECT 
  medication_type,
  COUNT(DISTINCT hadm_id) AS patient_count,
  SUM(CASE 
        WHEN starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 3 DAY) THEN 1 
        ELSE 0 
      END) AS first_72h_count,
  SUM(CASE 
        WHEN starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 3 DAY) AND dischtime THEN 1 
        ELSE 0 
      END) AS final_72h_count
FROM 
  medications
GROUP BY 
  medication_type;
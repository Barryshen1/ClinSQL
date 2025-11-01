WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime,
    a.dischtime,
    p.anchor_age, 
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 77 AND 87 
    AND p.gender = 'M'
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
            long_title IN ('Diabetes mellitus', 'Heart failure')
        )
    )
),

-- Identify medication administration
medication_admin AS (
  SELECT 
    subject_id, 
    hadm_id, 
    drug, 
    starttime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` 
  WHERE 
    drug_type = 'medication'
    AND drug LIKE '%Insulin%'  -- Assuming insulin is in the drug name
)

-- Calculate initiation rates and net change
SELECT 
  poi.subject_id, 
  poi.hadm_id, 
  ma.drug, 
  TIMESTAMP_DIFF(ma.starttime, poi.admittime, HOUR) AS start_time_hours
FROM 
  patients_of_interest poi
JOIN 
  medication_admin ma ON poi.subject_id = ma.subject_id AND poi.hadm_id = ma.hadm_id
WHERE 
  TIMESTAMP_DIFF(ma.starttime, poi.admittime, HOUR) BETWEEN 0 AND 48 
  OR TIMESTAMP_DIFF(poi.dischtime, ma.starttime, HOUR) BETWEEN 0 AND 72;
WITH 
-- Step 1: Identify patients of interest
patients_of_interest AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 43 AND 53
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
            long_title LIKE '%Hepatic Failure%'
        )
    )
),

-- Step 2: Compute medication complexity score
medication_complexity AS (
  SELECT 
    p.hadm_id, 
    p.subject_id, 
    COUNT(DISTINCT prs.drug) AS num_drugs
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` prs
  JOIN 
    patients_of_interest p 
      ON prs.hadm_id = p.hadm_id
  WHERE 
    prs.starttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 72 HOUR)
  GROUP BY 
    p.hadm_id, 
    p.subject_id
),

-- Step 3: Calculate LOS, mortality, and readmission
patient_outcomes AS (
  SELECT 
    poi.hadm_id, 
    poi.subject_id, 
    poi.dischtime, 
    poi.hospital_expire_flag,
    mc.num_drugs,
    TIMESTAMP_DIFF(poi.dischtime, poi.admittime, DAY) AS los
  FROM 
    patients_of_interest poi
  JOIN 
    medication_complexity mc 
      ON poi.hadm_id = mc.hadm_id
),

-- Step 4: Determine readmission
readmissions AS (
  SELECT 
    subject_id, 
    hadm_id, 
    dischtime, 
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY dischtime) AS next_admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Step 5: Final calculation
final_calculation AS (
  SELECT 
    NTILE(5) OVER (ORDER BY fc.num_drugs) AS quintile,
    COUNT(fc.subject_id) AS n,
    MIN(fc.num_drugs) AS min_score,
    MAX(fc.num_drugs) AS max_score,
    AVG(fc.num_drugs) AS mean_score,
    AVG(fc.los) AS mean_los,
    AVG(CASE WHEN fc.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality_rate,
    AVG(CASE 
        WHEN ra.next_admittime IS NOT NULL 
          AND TIMESTAMP_DIFF(ra.next_admittime, fc.dischtime, DAY) <= 30 
        THEN 1 
        ELSE 0 
      END) AS thirty_day_readmission_rate
  FROM 
    patient_outcomes fc
  LEFT JOIN 
    readmissions ra 
      ON fc.subject_id = ra.subject_id 
      AND fc.dischtime < ra.dischtime
  GROUP BY 
    NTILE(5) OVER (ORDER BY fc.num_drugs)
)

SELECT 
  quintile,
  n,
  min_score,
  max_score,
  mean_score,
  mean_los,
  in_hospital_mortality_rate,
  thirty_day_readmission_rate
FROM 
  final_calculation
ORDER BY 
  quintile;
WITH 
-- Filter patients with diabetes and heart failure
patients_with_conditions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 65 AND 75
    AND p.gender = 'F'
    AND a.dischtime - a.admittime >= INTERVAL 4 DAY
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

-- Identify insulin therapy types
insulin_therapy AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug,
    pr.route,
    ph.doses_per_24_hrs,
    ph.basal_rate,
    ph.infusion_type
  FROM 
    patients_with_conditions p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
      ON p.hadm_id = pr.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph 
      ON pr.hadm_id = ph.hadm_id AND pr.pharmacy_id = ph.pharmacy_id
  WHERE 
    pr.drug LIKE '%Insulin%'
),

-- Categorize insulin therapy
therapy_categories AS (
  SELECT 
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    drug,
    route,
    doses_per_24_hrs,
    basal_rate,
    infusion_type,
    CASE
      WHEN infusion_type = 'Basal' THEN 'Basal'
      WHEN infusion_type = 'Bolus' THEN 'Bolus'
      WHEN basal_rate > 0 AND doses_per_24_hrs > 0 THEN 'Basal-bolus'
      WHEN doses_per_24_hrs = 0 AND basal_rate > 0 THEN 'Basal'
      ELSE 'Sliding-scale'
    END AS therapy_type
  FROM 
    insulin_therapy
)

-- Analyze insulin administration patterns
SELECT 
  tc.therapy_type,
  COUNT(DISTINCT tc.hadm_id) AS num_patients,
  SUM(CASE WHEN tc.starttime - (p.admittime + INTERVAL 2 DAY) < INTERVAL 0 DAY AND tc.starttime - (p.admittime + INTERVAL 2 DAY) > INTERVAL -2 DAY THEN 1 ELSE 0 END) AS first_48h,
  SUM(CASE WHEN tc.starttime - (p.dischtime - INTERVAL 2 DAY) < INTERVAL 2 DAY AND tc.starttime - (p.dischtime - INTERVAL 2 DAY) > INTERVAL 0 DAY THEN 1 ELSE 0 END) AS final_48h
FROM 
  therapy_categories tc
  JOIN patients_with_conditions p ON tc.hadm_id = p.hadm_id
GROUP BY 
  tc.therapy_type;
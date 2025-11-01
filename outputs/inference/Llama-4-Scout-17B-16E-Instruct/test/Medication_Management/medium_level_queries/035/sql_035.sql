WITH 
  -- Identify target population
  target_patients AS (
    SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    WHERE p.gender = 'F' AND p.anchor_age BETWEEN 57 AND 67
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code IN (
        SELECT icd_code 
        FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
        WHERE long_title IN ('Diabetes mellitus', 'Heart failure')
      )
    )
  ),

  -- GLP-1 RA prescriptions
  glp1_ra_prescriptions AS (
    SELECT p.hadm_id,
           COUNT(DISTINCT p.hadm_id) AS patient_count,
           SUM(CASE WHEN p.starttime BETWEEN tp.admittime AND TIMESTAMP_ADD(tp.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS first_48h_count,
           SUM(CASE WHEN p.starttime BETWEEN TIMESTAMP_SUB(tp.dischtime, INTERVAL 12 HOUR) AND tp.dischtime THEN 1 ELSE 0 END) AS final_12h_count
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN target_patients tp ON p.hadm_id = tp.hadm_id
    WHERE p.drug LIKE '%GLP-1%'
    GROUP BY p.hadm_id
  )

-- Calculate prevalence and change
SELECT 
  COALESCE(gp.first_48h_count, 0) AS first_48h_prevalence,
  COALESCE(gp.final_12h_count, 0) AS final_12h_prevalence,
  COALESCE(gp.final_12h_count, 0) - COALESCE(gp.first_48h_count, 0) AS absolute_change,
  IF(COALESCE(gp.first_48h_count, 0) = 0, 
     COALESCE(gp.final_12h_count, 0), 
     (COALESCE(gp.final_12h_count, 0) - COALESCE(gp.first_48h_count, 0)) / COALESCE(gp.first_48h_count, 0)) * 100 AS relative_change
FROM 
  glp1_ra_prescriptions gp;
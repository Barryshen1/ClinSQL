WITH 
  -- Define injectable GLP-1 RA
  glp1_ra AS (
    SELECT 
      drug 
    FROM 
      `physionet-data.mimiciv_3_1_hosp.prescriptions`
    GROUP BY 
      drug 
    HAVING 
      REGEXP_CONTAINS(LOWER(drug), r'glp-1|exenatide|liraglutide|dulaglutide|semaglutide|inject')
  ),

  -- Identify patients of interest
  patients_of_interest AS (
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
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 53 AND 63
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

  -- Identify prescriptions for GLP-1 RA in first 24 hours or last 12 hours
  glp1_ra_prescriptions AS (
    SELECT 
      p.subject_id, 
      p.hadm_id,
      p.admittime,
      p.dischtime,
      pr.starttime,
      CASE 
        WHEN pr.starttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 1 DAY) THEN 'first_24hrs'
        WHEN pr.starttime BETWEEN TIMESTAMP_SUB(p.dischtime, INTERVAL 12 HOUR) AND p.dischtime THEN 'last_12hrs'
        ELSE 'other'
      END AS prescription_timing
    FROM 
      patients_of_interest p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
      ON p.hadm_id = pr.hadm_id
    JOIN 
      glp1_ra g 
      ON pr.drug = g.drug
  )

SELECT 
  COALESCE(SUM(CASE WHEN prescription_timing = 'first_24hrs' THEN 1 ELSE 0 END) * 100.0 / 
  COUNT(DISTINCT hadm_id), 0) AS pct_first_24hrs,
  COALESCE(SUM(CASE WHEN prescription_timing = 'last_12hrs' THEN 1 ELSE 0 END) * 100.0 / 
  COUNT(DISTINCT hadm_id), 0) AS pct_last_12hrs
FROM 
  glp1_ra_prescriptions;
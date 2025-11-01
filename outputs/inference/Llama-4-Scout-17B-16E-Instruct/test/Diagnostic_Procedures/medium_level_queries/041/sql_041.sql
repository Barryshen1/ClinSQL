WITH 
  -- Filter admissions for males aged 51-61 with acute pancreatitis
  filtered_admissions AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.anchor_age,
      p.gender,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 51 AND 61
      AND a.hospital_expire_flag = 0
  ),
  
  -- Identify acute pancreatitis and categorize as primary or secondary
  pancreatitis_admissions AS (
    SELECT 
      fa.hadm_id,
      fa.admittime,
      fa.dischtime,
      CASE 
        WHEN di.seq_num = 1 THEN 'Primary'
        ELSE 'Secondary'
      END AS diagnosis_type
    FROM 
      filtered_admissions fa
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        ON fa.hadm_id = di.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE 
      dd.long_title LIKE '%Acute pancreatitis%'
  ),
  
  -- Calculate LOS and categorize
  los_categories AS (
    SELECT 
      pa.hadm_id,
      pa.diagnosis_type,
      TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY) AS los
    FROM 
      pancreatitis_admissions pa
  ),
  
  -- Identify radiography/CTs
  radiography_cts AS (
    SELECT 
      s.hadm_id,
      COUNT(s.curr_service) AS radiography_ct_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.services` s
    WHERE 
      LOWER(s.curr_service) LIKE '%radiology%' 
      OR LOWER(s.curr_service) LIKE '%ct%'
    GROUP BY 
      s.hadm_id
  ),
  
  final_query AS (
    SELECT 
      lc.hadm_id,
      lc.diagnosis_type,
      lc.los,
      IFNULL(rct.radiography_ct_count, 0) AS radiography_ct_count
    FROM 
      los_categories lc
    LEFT JOIN 
      radiography_cts rct ON lc.hadm_id = rct.hadm_id
  )

SELECT 
  diagnosis_type,
  COUNT(DISTINCT hadm_id) AS patient_count,
  AVG(radiography_ct_count) AS mean_radiography_cts,
  CASE 
    WHEN los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Outside range'
  END AS los_category
FROM 
  final_query
GROUP BY 
  diagnosis_type,
  los_category
ORDER BY 
  diagnosis_type,
  los_category;
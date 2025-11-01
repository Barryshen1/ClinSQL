WITH 
  -- Identify AKI ICD codes
  aki_icd_codes AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE long_title LIKE '%Acute kidney injury%'
  ),
  
  -- Identify diagnostic imaging studies
  imaging_studies AS (
    SELECT 
      p.subject_id,
      p.hadm_id,
      COUNT(DISTINCT p.icd_code) AS num_imaging_studies
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON 
      p.icd_code = d.icd_code
    WHERE 
      d.long_title LIKE '% Imaging%'  -- Filter for imaging studies
    GROUP BY 
      p.subject_id, p.hadm_id
  ),
  
  -- Identify AKI admissions and duration
  aki_admissions AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      CASE 
        WHEN EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
          WHERE di.hadm_id = a.hadm_id AND di.icd_code IN (SELECT icd_code FROM aki_icd_codes)
        ) THEN 'primary'
        ELSE 'secondary'
      END AS diagnosis_type
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    WHERE 
      a.subject_id IN (
        SELECT subject_id
        FROM `physionet-data.mimiciv_3_1_hosp.patients`
        WHERE gender = 'F' AND anchor_age BETWEEN 64 AND 74
      )
  ),
  
  -- Calculate AKI duration and categorize
  aki_duration AS (
    SELECT 
      hadm_id,
      diagnosis_type,
      DATE_DIFF(dischtime, admittime, DAY) AS aki_duration
    FROM 
      aki_admissions
  )

-- Final query
SELECT 
  CASE 
    WHEN aki_duration BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN aki_duration BETWEEN 4 AND 7 THEN '4-7 days'
  END AS aki_duration_category,
  diagnosis_type,
  APPROX_QUANTILES(num_imaging_studies, 0.5)[OFFSET(1)] AS median_imaging_studies,
  APPROX_QUANTILES(num_imaging_studies, 0.25)[OFFSET(1)] AS q1_imaging_studies,
  APPROX_QUANTILES(num_imaging_studies, 0.75)[OFFSET(1)] AS q3_imaging_studies
FROM 
  aki_duration
JOIN 
  imaging_studies
ON 
  aki_duration.hadm_id = imaging_studies.hadm_id
GROUP BY 
  aki_duration_category, diagnosis_type;
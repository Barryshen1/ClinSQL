WITH 
  -- Identify AMI patients without shock or respiratory failure
  ami_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.anchor_age,
      p.gender,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 78 AND 88
      AND a.hospital_expire_flag = 0
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE 
          d.hadm_id = a.hadm_id
          AND d.icd_code LIKE '410%'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE 
          d.hadm_id = a.hadm_id
          AND d.icd_code IN ('785.52', '518.81', '518.82', '96.71')
      )
  ),
  
  -- Calculate comorbidity burden
  comorbidity_burden AS (
    SELECT 
      subject_id,
      hadm_id,
      COUNT(DISTINCT icd_code) AS comorbidity_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY 
      subject_id, hadm_id
  ),
  
  -- Categorize comorbidity burden
  categorized_comorbidities AS (
    SELECT 
      cb.subject_id,
      cb.hadm_id,
      CASE 
        WHEN cb.comorbidity_count <= 2 THEN 'low'
        WHEN cb.comorbidity_count BETWEEN 3 AND 5 THEN 'med'
        ELSE 'high'
      END AS comorbidity_burden
    FROM 
      comorbidity_burden cb
  ),
  
  -- Calculate length of stay (LOS)
  los AS (
    SELECT 
      subject_id,
      hadm_id,
      timestamp_diff(COALESCE(dischtime, deathtime), admittime, DAY) AS los_days
    FROM 
      ami_patients
  ),
  
  -- Combine data
  combined_data AS (
    SELECT 
      c.comorbidity_burden,
      a.hospital_expire_flag,
      l.los_days
    FROM 
      ami_patients a
    JOIN 
      los l ON a.hadm_id = l.hadm_id
    JOIN 
      categorized_comorbidities c ON a.hadm_id = c.hadm_id
  )

-- Final query
SELECT 
  comorbidity_burden,
  AVG(hospital_expire_flag) AS mortality_rate,
  APPROX_QUANTILES(los_days, 4) AS los_quantiles
FROM 
  combined_data
GROUP BY 
  comorbidity_burden
ORDER BY 
  comorbidity_burden;
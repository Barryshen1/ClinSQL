WITH 
  -- Define admissions of interest
  admissions_of_interest AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.admission_type,
      a.admit_provider_id,
      a.admission_location,
      a.discharge_location,
      a.insurance,
      a.language,
      a.marital_status,
      a.race,
      a.edregtime,
      a.edouttime,
      a.hospital_expire_flag,
      p.gender,
      p.anchor_age,
      p.anchor_year,
      p.dod,
      CASE 
        WHEN a.admission_type = 'Transfer in' THEN TRUE
        ELSE FALSE
      END AS transferred_in
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 76 AND 86
      AND a.insurance LIKE '%Medicare%'
      AND (a.admission_type = 'Transfer in')
  ),
  
  -- Identify principal AMI
  ami_admissions AS (
    SELECT 
      hadm_id,
      subject_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      (icd_code LIKE '410%' AND icd_version = 9) 
      OR (icd_code LIKE 'I21%' AND icd_version = 10)
    AND seq_num = 1
  ),
  
  -- Merge admissions of interest with AMI
  merged_data AS (
    SELECT 
      aoi.hadm_id,
      aoi.subject_id,
      aoi.dischtime,
      aoi.admittime,
      TIMESTAMPDIFF(DAY, aoi.admittime, aoi.dischtime) AS los
    FROM 
      admissions_of_interest aoi
    INNER JOIN 
      ami_admissions ami 
      ON aoi.hadm_id = ami.hadm_id
  ),
  
  -- Identify readmissions within 30 days
  readmissions AS (
    SELECT 
      hadm_id,
      MIN(admittime) AS readmit_time
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY 
      hadm_id
  ),
  
  -- Flag readmitted patients
  flagged_readmissions AS (
    SELECT 
      md.hadm_id,
      CASE 
        WHEN r.readmit_time IS NOT NULL AND r.readmit_time <= TIMESTAMP_ADD(md.dischtime, INTERVAL 30 DAY) THEN TRUE
        ELSE FALSE
      END AS readmitted
    FROM 
      merged_data md
    LEFT JOIN 
      readmissions r 
      ON md.hadm_id = r.hadm_id
  )

SELECT 
  COUNT(DISTINCT CASE WHEN readmitted THEN hadm_id END) / 
    COUNT(DISTINCT hadm_id) AS thirty_day_readmission_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_los_overall,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) FILTER (WHERE readmitted) AS median_los_readmitted,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) FILTER (WHERE NOT readmitted) AS median_los_not_readmitted,
  AVG(CAST(los > 4 AS INT64)) * 100 AS percent_stays_greater_than_four_days
FROM 
  flagged_readmissions
CROSS JOIN 
  merged_data
ON 
  flagged_readmissions.hadm_id = merged_data.hadm_id;
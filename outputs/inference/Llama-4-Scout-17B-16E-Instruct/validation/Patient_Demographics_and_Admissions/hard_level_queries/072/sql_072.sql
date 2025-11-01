WITH 
  -- Filter target patients
  target_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.admission_location,
      a.insurance,
      p.anchor_age,
      p.gender,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 77 AND 87
      AND a.admission_location = 'SNF'
      AND a.insurance = 'Medicare'
  ),

  -- Identify principal diagnosis of acute respiratory failure
  acute_respiratory_failure AS (
    SELECT 
      subject_id,
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    ON 
      diagnoses_icd.icd_code = d_icd_diagnoses.icd_code
      AND diagnoses_icd.icd_version = d_icd_diagnoses.icd_version
    WHERE 
      d_icd_diagnoses.long_title LIKE '%Acute respiratory failure%'
      AND diagnoses_icd.seq_num = 1  -- Principal diagnosis
  ),

  -- Identify readmissions within 30 days
  readmissions AS (
    SELECT 
      a1.subject_id,
      a2.admittime AS readmit_time,
      a1.dischtime
    FROM 
      target_patients a1
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON 
      a1.subject_id = a2.subject_id
    WHERE 
      a2.admittime BETWEEN TIMESTAMP_ADD(a1.dischtime, INTERVAL 1 DAY) 
                         AND TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
  ),

  -- Prepare data for calculations
  patient_stays AS (
    SELECT 
      tp.subject_id,
      tp.hadm_id,
      tp.dischtime,
      tp.admittime,
      CASE 
        WHEN r.subject_id IS NOT NULL THEN TRUE 
        ELSE FALSE 
      END AS readmitted
    FROM 
      target_patients tp
    JOIN 
      acute_respiratory_failure arf 
        ON tp.subject_id = arf.subject_id AND tp.hadm_id = arf.hadm_id
    LEFT JOIN 
      readmissions r 
        ON tp.subject_id = r.subject_id
  )

-- Calculate readmission rate, median LOS, and percent stays > 8 days
SELECT 
  COUNT(DISTINCT CASE WHEN ps.readmitted THEN ps.subject_id END) AS readmitted_patients,
  COUNT(DISTINCT ps.subject_id) AS total_patients,
  COUNT(DISTINCT CASE WHEN ps.readmitted THEN ps.hadm_id END) / 
  COUNT(DISTINCT ps.hadm_id) AS readmission_rate,
  PERCENTILE_CONT(0.5)(ARRAY_AGG(CASE WHEN ps.readmitted THEN DATE_DIFF(ps.dischtime, ps.admittime) END IGNORE NULLS)) AS median_los_readmitted,
  PERCENTILE_CONT(0.5)(ARRAY_AGG(CASE WHEN NOT ps.readmitted THEN DATE_DIFF(ps.dischtime, ps.admittime) END IGNORE NULLS)) AS median_los_not_readmitted,
  AVG(CAST(CASE WHEN ps.readmitted AND DATE_DIFF(ps.dischtime, ps.admittime) > 8 THEN 1 ELSE 0 END AS FLOAT64)) AS percent_stays_over_8_days_readmitted,
  AVG(CAST(CASE WHEN NOT ps.readmitted AND DATE_DIFF(ps.dischtime, ps.admittime) > 8 THEN 1 ELSE 0 END AS FLOAT64)) AS percent_stays_over_8_days_not_readmitted
FROM 
  patient_stays ps;
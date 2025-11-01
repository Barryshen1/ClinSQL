WITH eligible_patients AS (
  -- Filter patients: female, Medicare, age 61-71
  SELECT DISTINCT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 61 AND 71
    AND dod IS NULL  -- Exclude deceased patients entirely for clean cohort
),
aki_codes AS (
  -- ICD-10 codes for AKI (principal diagnosis) - refined to relevant codes
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = '10'
    AND (icd_code LIKE 'N17.%'  -- Acute kidney failure
         OR icd_code LIKE 'T79.5%')  -- Traumatic anuria/oliguria
),
index_admissions AS (
  -- Qualifying index admissions: from SNF, no in-hospital death, principal AKI dx
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  INNER JOIN aki_codes aki ON d.icd_code = aki.icd_code AND d.icd_version = '10'
  WHERE a.admission_location = 'SNF'
    AND a.hospital_expire_flag = 0
),
readmissions AS (
  -- Flag first readmission within 30 days per patient
  SELECT 
    i.subject_id,
    i.hadm_id AS index_hadm_id,
    i.admittime AS index_admittime,
    i.dischtime AS index_dischtime,
    i.los_days AS index_los,
    MIN(r.hadm_id) OVER (PARTITION BY i.subject_id) AS readm_hadm_id,
    MIN(r.admittime) OVER (PARTITION BY i.subject_id) AS first_readm_time
  FROM index_admissions i
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` r 
    ON i.subject_id = r.subject_id 
    AND r.admittime > i.dischtime 
    AND r.admittime <= DATE_ADD(i.dischtime, INTERVAL 30 DAY)
    AND r.hospital_expire_flag = 0  -- Exclude death on readmission
),
flagged_cohorts AS (
  -- Determine readmitted status
  SELECT 
    *,
    CASE 
      WHEN first_readm_time IS NOT NULL THEN 1 
      ELSE 0 
    END AS readmitted
  FROM readmissions
)
SELECT 
  -- Readmission rate
  SAFE_DIVIDE(SUM(readmitted), COUNT(*)) AS readmission_rate,
  
  -- Median LOS for readmitted
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY index_los) OVER (ORDER BY readmitted) FILTER (WHERE readmitted = 1) AS median_los_readmitted,
  No, wait—actually, for conditional percentiles in BigQuery, better to use separate aggregations:
  
  Actually, the cleanest fix is:
  
  PERCENTILE_CONT(index_los, 0.5) IGNORE NULLS 
  FILTER (WHERE readmitted = 1) AS median_los_readmitted,
  
  PERCENTILE_CONT(index_los, 0.5) IGNORE NULLS 
  FILTER (WHERE readmitted = 0) AS median_los_non_readmitted,
  
  -- % index stays >6 days
  SAFE_DIVIDE(SUM(CASE WHEN index_los > 6 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS pct_stays_over_6_days

FROM flagged_cohorts;
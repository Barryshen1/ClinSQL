WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Categorize LOS
    CASE 
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8'
      ELSE 'Other' 
    END AS los_group,
    -- Get the ACS diagnosis with the smallest seq_num for this admission
    MIN(CASE WHEN d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I23%' OR d.icd_code LIKE '410%' THEN d.seq_num END) AS acs_seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (d.icd_code LIKE 'I21%' 
         OR d.icd_code LIKE 'I22%' 
         OR d.icd_code LIKE 'I23%' 
         OR d.icd_code LIKE '410%')
  GROUP BY p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime
  HAVING acs_seq_num IS NOT NULL  -- Ensure at least one ACS diagnosis
),

-- Count procedures per admission
proc_counts AS (
  SELECT 
    c.hadm_id,
    c.los_group,
    -- Classify diagnosis type based on the smallest seq_num for ACS
    CASE WHEN c.acs_seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS diagnosis_type,
    COUNT(DISTINCT p.seq_num) AS num_procedures
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON c.hadm_id = p.hadm_id
  WHERE c.los_group IN ('1-4', '5-8')  -- Only include the two LOS groups of interest
  GROUP BY c.hadm_id, c.los_group, diagnosis_type
)

-- Compute percentiles stratified by LOS group and diagnosis type
SELECT 
  los_group,
  diagnosis_type,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS p75,
  COUNT(*) AS num_admissions
FROM proc_counts
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;
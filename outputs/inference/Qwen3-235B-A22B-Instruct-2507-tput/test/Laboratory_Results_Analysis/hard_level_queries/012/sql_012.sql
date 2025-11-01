WITH
  -- Step 1: Get patients with AMI (ICD-10 I21, I22)
  ami_codes AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE (
      icd_code LIKE 'I21%' OR 
      icd_code LIKE 'I22%'
    )
    AND icd_version = 10
  ),
  
  -- Step 2: Cohort of male patients aged 44–54
  age_gender_cohort AS (
    SELECT p.subject_id, p.anchor_age, p.anchor_year, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 44 AND 54
      AND a.admittime IS NOT NULL
  ),
  
  -- Step 3: AMI cohort
  ami_cohort AS (
    SELECT ag.*
    FROM age_gender_cohort ag
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON ag.hadm_id = di.hadm_id
    INNER JOIN ami_codes ac
      ON di.icd_code = ac.icd_code AND di.icd_version = 10
  ),
  
  -- Step 4: General inpatient control cohort (same age/gender, no AMI)
  control_cohort AS (
    SELECT ag.*
    FROM age_gender_cohort ag
    WHERE NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN ami_codes ac ON di.icd_code = ac.icd_code AND di.icd_version = 10
      WHERE di.hadm_id = ag.hadm_id
    )
  ),
  
  -- Step 5: Lab events within first 72 hours
  labs_72h AS (
    SELECT 
      le.subject_id,
      le.hadm_id,
      le.charttime,
      le.itemid,
      le.valuenum,
      le.ref_range_lower,
      le.ref_range_upper,
      le.flag,
      d.label
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
      ON le.itemid = d.itemid
    WHERE le.valuenum IS NOT NULL
      AND le.charttime IS NOT NULL
  ),
  
  -- Step 6: Join labs with AMI cohort to get first 72h
  ami_labs AS (
    SELECT 
      l.*
    FROM labs_72h l
    INNER JOIN ami_cohort a
      ON l.hadm_id = a.hadm_id
    WHERE l.charttime >= a.admittime 
      AND l.charttime <= DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
  ),
  
  -- Step 7: Flag abnormal labs (out of reference range)
  ami_labs_abnormal AS (
    SELECT *,
      CASE 
        WHEN valuenum < ref_range_lower OR valuenum > ref_range_upper THEN 1
        ELSE 0
      END AS is_abnormal
    FROM ami_labs
  ),
  
  -- Step 8: Aggregate per patient in AMI cohort: abnormal count, critical flag count
  ami_lab_stats AS (
    SELECT
      subject_id,
      hadm_id,
      COUNT(*) AS total_labs,
      SUM(is_abnormal) AS abnormal_count,
      COUNTIF(flag IN ('abnormal', 'critical')) AS critical_count
    FROM ami_labs_abnormal
    GROUP BY subject_id, hadm_id
  ),
  
  -- Step 9: Control cohort labs (first 72h)
  control_labs AS (
    SELECT 
      l.*
    FROM labs_72h l
    INNER JOIN control_cohort c
      ON l.hadm_id = c.hadm_id
    WHERE l.charttime >= c.admittime 
      AND l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  ),
  
  control_labs_abnormal AS (
    SELECT *,
      CASE 
        WHEN valuenum < ref_range_lower OR valuenum > ref_range_upper THEN 1
        ELSE 0
      END AS is_abnormal
    FROM control_labs
  ),
  
  control_lab_stats AS (
    SELECT
      subject_id,
      hadm_id,
      COUNT(*) AS total_labs,
      SUM(is_abnormal) AS abnormal_count,
      COUNTIF(flag IN ('abnormal', 'critical')) AS critical_count
    FROM control_labs_abnormal
    GROUP BY subject_id, hadm_id
  ),
  
  -- Step 10: Cohort-level summaries
  ami_summary AS (
    SELECT
      APPROX_QUANTILES(CAST(abnormal_count AS FLOAT64), 100)[OFFSET(75)] AS lab_instability_score_p75,
      AVG(critical_count) AS avg_critical_lab_count_ami,
      APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0, 100)[OFFSET(50)] AS median_los_days,
      AVG(hospital_expire_flag) AS mortality_rate_ami
    FROM ami_cohort
    LEFT JOIN ami_lab_stats USING (subject_id, hadm_id)
  ),
  control_summary AS (
    SELECT
      AVG(critical_count) AS avg_critical_lab_count_control
    FROM control_cohort
    LEFT JOIN control_lab_stats USING (subject_id, hadm_id)
  )
SELECT
  lab_instability_score_p75,
  avg_critical_lab_count_ami,
  avg_critical_lab_count_control,
  median_los_days,
  mortality_rate_ami
FROM ami_summary, control_summary;
WITH cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.insurance,
    a.admission_location,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    -- Calculate length of stay in days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      -- Principal diagnosis (seq_num=1) for AMI
      seq_num = 1 AND (
        (icd_version = 9 AND icd_code LIKE '410%') OR 
        (icd_version = 10 AND icd_code LIKE 'I21%')
      )
  ) diag 
    ON a.hadm_id = diag.hadm_id
  WHERE 
    a.admission_location = 'TRANSFER FROM HOSPITAL' 
    AND a.insurance = 'Medicare'
    AND p.gender = 'F'
    -- Exclude in-hospital deaths (no readmission possible)
    AND a.hospital_expire_flag = 0
    -- Age 76-86 at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 76 AND 86
),

cohort_with_readmission AS (
  SELECT 
    *,
    -- Flag readmissions within 30 days of discharge
    CASE 
      WHEN DATE_DIFF(
        LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime), 
        dischtime, 
        DAY
      ) <= 30 THEN 1 
      ELSE 0 
    END AS readmission_flag
  FROM cohort
)

SELECT
  -- 30-day readmission rate (%)
  ROUND(100 * AVG(readmission_flag), 2) AS readmission_rate_percent,
  -- Median LOS for readmitted patients (using approximate median)
  APPROX_QUANTILES(IF(readmission_flag=1, los, NULL), 100)[OFFSET(50)] AS median_los_readmitted,
  -- Median LOS for non-readmitted patients
  APPROX_QUANTILES(IF(readmission_flag=0, los, NULL), 100)[OFFSET(50)] AS median_los_not_readmitted,
  -- % of index stays with LOS > 4 days
  ROUND(100 * AVG(CASE WHEN los > 4 THEN 1.0 ELSE 0.0 END), 2) AS percent_los_gt_4
FROM cohort_with_readmission;
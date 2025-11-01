WITH
-- Define hepatic failure ICD codes
hepatic_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%hepatic failure%'
     OR long_title LIKE '%liver failure%'
     OR icd_code IN ('K72.90', 'K72.91', 'K72.10', 'K72.11', 'K72.0', 'K72.9')
),

-- Identify cohort: female inpatients aged 80-90 with hepatic failure
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN hepatic_failure_codes h ON d.icd_code = h.icd_code
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND d.seq_num = 1  -- Primary diagnosis
    AND a.dischtime IS NOT NULL
),

-- Calculate 7-day medication complexity score
med_complexity AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    -- Count distinct medications
    COUNT(DISTINCT pr.drug) AS unique_med_count,
    -- Sum of doses per day (simplified complexity metric)
    SUM(pr.doses_per_24_hrs) AS total_doses_per_day,
    -- Additional complexity factors could be added here
    COUNT(DISTINCT pr.route) AS route_variety
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  WHERE
    pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY c.subject_id, c.hadm_id
),

-- Combine complexity metrics into a single score
complexity_score AS (
  SELECT
    subject_id,
    hadm_id,
    -- Simple weighted score (can be refined)
    (unique_med_count * 1.0 + total_doses_per_day * 0.5 + route_variety * 0.3) AS complexity_score
  FROM med_complexity
),

-- Stratify into tertiles
tertile_stratification AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    cs.complexity_score,
    NTILE(3) OVER (ORDER BY cs.complexity_score) AS complexity_tertile,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = c.subject_id
          AND a2.admittime > c.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0
    END AS readmitted_30d
  FROM cohort c
  JOIN complexity_score cs ON c.subject_id = cs.subject_id AND c.hadm_id = cs.hadm_id
)

-- Final results
SELECT
  complexity_tertile,
  COUNT(*) AS patient_count,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
  SUM(hospital_expire_flag) / COUNT(*) AS in_hospital_mortality_rate,
  SUM(readmitted_30d) / COUNT(*) AS readmission_30d_rate
FROM tertile_stratification
GROUP BY complexity_tertile
ORDER BY complexity_tertile;
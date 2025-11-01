WITH hf_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%heart failure%'
),
hf_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN hf_codes h
    ON d.icd_code = h.icd_code AND d.icd_version = h.icd_version
),
first_hf AS (
  SELECT *
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC) AS rn
    FROM hf_admissions
  )
  WHERE rn = 1
),
cohort AS (
  SELECT 
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.dischtime,
    (EXTRACT(YEAR FROM f.admittime) - p.anchor_year + p.anchor_age) AS age_at_admit
  FROM first_hf f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON f.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM f.admittime) - p.anchor_year + p.anchor_age) BETWEEN 38 AND 48
    AND f.hospital_expire_flag = 0
    AND f.dischtime IS NOT NULL
),
cohort_with_readmit AS (
  SELECT 
    c.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = c.subject_id
          AND a2.hadm_id != c.hadm_id
          AND a2.admittime > c.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM cohort c
)
SELECT 
  COUNT(*) AS total_patients,
  SUM(readmitted_30d) AS num_readmitted,
  ROUND(SUM(readmitted_30d) * 100.0 / COUNT(*), 2) AS readmission_rate_percent
FROM cohort_with_readmit;
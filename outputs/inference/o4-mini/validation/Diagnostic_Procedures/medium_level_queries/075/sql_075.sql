WITH acs_codes AS (
  -- Identify ICD codes corresponding to ACS via the long_title
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%acute coronary%'
),
acs_admissions AS (
  -- Find all admissions with at least one ACS diagnosis and determine the earliest seq_num
  SELECT
    d.subject_id,
    d.hadm_id,
    MIN(d.seq_num) AS min_acs_seq
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN acs_codes a
    ON d.icd_code = a.icd_code
   AND d.icd_version = a.icd_version
  GROUP BY d.subject_id, d.hadm_id
),
filtered_admissions AS (
  -- Base admissions filtered by gender, age, ACS presence, and compute LOS & grouping
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    CASE
      WHEN aa.min_acs_seq = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_position,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN acs_admissions aa
    ON a.subject_id = aa.subject_id
   AND a.hadm_id = aa.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
),
admissions_los_buckets AS (
  -- Restrict to LOS 1–7 days and create 1-3 vs 4-7 buckets
  SELECT
    subject_id,
    hadm_id,
    diagnosis_position,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_bucket
  FROM filtered_admissions
  WHERE los_days BETWEEN 1 AND 7
),
proc_counts AS (
  -- Count diagnostic procedures (ICD) per admission
  SELECT
    pb.subject_id,
    pb.hadm_id,
    pb.diagnosis_position,
    pb.los_bucket,
    COUNT(*) AS proc_count
  FROM admissions_los_buckets pb
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON pb.subject_id = pr.subject_id
   AND pb.hadm_id = pr.hadm_id
  GROUP BY pb.subject_id, pb.hadm_id, pb.diagnosis_position, pb.los_bucket
),
quantiles_by_group AS (
  -- Compute approximate quartiles of procedure counts
  SELECT
    los_bucket,
    diagnosis_position,
    APPROX_QUANTILES(proc_count, 4) AS quantile_array
  FROM proc_counts
  GROUP BY los_bucket, diagnosis_position
)
SELECT
  los_bucket,
  diagnosis_position,
  quantile_array[OFFSET(1)] AS p25_procs,
  quantile_array[OFFSET(2)] AS p50_procs,
  quantile_array[OFFSET(3)] AS p75_procs
FROM quantiles_by_group
ORDER BY los_bucket, diagnosis_position;
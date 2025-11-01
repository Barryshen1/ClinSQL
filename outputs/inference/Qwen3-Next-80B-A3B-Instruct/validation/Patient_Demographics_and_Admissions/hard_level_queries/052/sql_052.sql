WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_location,
    a.insurance,
    p.anchor_age,
    p.anchor_year,
    -- Compute age at this admission
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission,
    d.icd_code,
    d.icd_version
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE
    p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'Emergency Room'
    AND d.seq_num = 1
    AND LOWER(d_icd.long_title) LIKE '%acute pancreatitis%'
    AND a.hospital_expire_flag = 0  -- Exclude patients who died during admission
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 51 AND 61
),
admissions_with_next AS (
  SELECT
    *,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM
    index_admissions
),
readmission_flag AS (
  SELECT
    *,
    CASE
      WHEN next_admittime IS NOT NULL AND next_admittime <= dischtime + INTERVAL '30 day' THEN 1
      ELSE 0
    END AS readmitted_30d,
    EXTRACT(DAY FROM (dischtime - admittime)) AS los_days
  FROM
    admissions_with_next
)
SELECT
  SUM(readmitted_30d) * 1.0 / COUNT(*) AS readmission_rate_30d,
  PERCENTILE_CONT(los_days, 0.5) FILTER (WHERE readmitted_30d = 1) AS median_los_readmitted,
  PERCENTILE_CONT(los_days, 0.5) FILTER (WHERE readmitted_30d = 0) AS median_los_non_readmitted,
  SUM(CASE WHEN los_days > 9 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_stays_gt_9_days
FROM
  readmission_flag;
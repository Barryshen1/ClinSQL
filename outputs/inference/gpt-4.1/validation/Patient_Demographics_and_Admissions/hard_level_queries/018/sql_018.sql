WITH femoral_neck_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    -- ICD-10 S72.0xx
    (icd_version = 10 AND icd_code LIKE 'S72.0%')
    -- ICD-9 820.0x
    OR (icd_version = 9 AND icd_code LIKE '820.0%')
),
index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.insurance,
    a.admission_type,
    a.admission_location,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Age at admission (approximate, as anchor_age is at anchor_year)
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admit,
    -- LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
    AND d.seq_num = 1 -- principal diagnosis
  JOIN femoral_neck_icd icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 58 AND 68
    AND LOWER(a.insurance) LIKE '%medicare%'
    AND (
      LOWER(a.admission_type) = 'emergency'
      OR LOWER(a.admission_location) LIKE '%emergency%'
    )
    AND (a.hospital_expire_flag = 0 OR a.deathtime IS NULL)
),
readmissions AS (
  -- For each index admission, find the first subsequent admission within 30 days
  SELECT
    idx.subject_id,
    idx.hadm_id AS index_hadm_id,
    idx.dischtime AS index_dischtime,
    MIN(a.admittime) AS readmit_admittime,
    MIN(a.hadm_id) AS readmit_hadm_id
  FROM index_admissions idx
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON idx.subject_id = a.subject_id
    AND a.admittime > idx.dischtime
    AND DATETIME_DIFF(a.admittime, idx.dischtime, DAY) <= 30
  GROUP BY idx.subject_id, idx.hadm_id, idx.dischtime
),
final_cohort AS (
  SELECT
    idx.*,
    CASE WHEN r.readmit_hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted
  FROM index_admissions idx
  LEFT JOIN readmissions r
    ON idx.subject_id = r.subject_id
    AND idx.hadm_id = r.index_hadm_id
)
SELECT
  COUNT(*) AS n_index_admissions,
  ROUND(SUM(readmitted) / COUNT(*) * 100, 2) AS readmission_rate_percent,
  -- Median LOS for readmitted
  APPROX_QUANTILES(IF(readmitted=1, los, NULL), 2)[OFFSET(1)] AS median_los_readmitted,
  -- Median LOS for non-readmitted
  APPROX_QUANTILES(IF(readmitted=0, los, NULL), 2)[OFFSET(1)] AS median_los_nonreadmitted,
  -- Percent of index stays >8 days
  ROUND(SUM(CASE WHEN los > 8 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS percent_los_gt_8_days
FROM final_cohort;
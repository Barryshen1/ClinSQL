WITH diag_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%acute respiratory failure%'
    AND icd_version = 10
),
qualified_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) > 8 THEN 1 
      ELSE 0 
    END AS los_gt_8,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS adm_seq
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN diag_codes dc ON di.icd_code = dc.icd_code
  WHERE p.gender = 'F'
    AND a.dischtime IS NOT NULL
    AND a.admittime <= p.dod  -- avoid admissions after death
    AND a.admission_location LIKE '%SKILLED NURSING FACILITY%'
    AND a.insurance = 'Medicare'
    AND di.seq_num = 1  -- principal diagnosis
    AND di.icd_version = 10
    -- Compute age at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
),
index_admissions AS (
  SELECT *
  FROM qualified_admissions
  WHERE adm_seq = 1  -- first (index) admission
),
readmission_flag AS (
  SELECT
    ia.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = ia.subject_id
          AND a2.admittime > ia.dischtime
          AND a2.admittime <= DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM index_admissions ia
)
SELECT
  -- 30-day all-cause readmission rate
  AVG(CAST(readmitted_30d AS FLOAT64)) AS readmission_rate_30d,
  -- Median index LOS, by readmission status
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los_days END, 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los_days END, 2)[OFFSET(1)] AS median_los_not_readmitted,
  -- Percent of index stays with LOS > 8 days
  AVG(CAST(los_gt_8 AS FLOAT64)) AS pct_los_gt_8_days
FROM readmission_flag;
WITH cohort AS (
  -- Base cohort: female Medicare patients aged 76-86 with principal AMI, transferred from hospital, discharged alive
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id AS index_hadm_id,
    a.admittime AS index_admittime,
    a.dischtime AS index_dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS index_los_days,
    -- Confirm has ICU stay
    CASE WHEN t.careunit IS NOT NULL THEN 1 ELSE 0 END AS has_icu
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.transfers` t
    ON a.subject_id = t.subject_id 
    AND a.hadm_id = t.hadm_id 
    AND t.eventtype = 'admit' 
    AND t.careunit IS NOT NULL
  WHERE p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.admission_location = 'TRANSFER FROM HOSP'
    AND a.hospital_expire_flag = 0
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%') OR 
      (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
),
index_admissions AS (
  -- Deduplicate to earliest index admission per patient
  SELECT 
    subject_id,
    index_hadm_id,
    index_admittime,
    index_dischtime,
    index_los_days
  FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY index_admittime ASC) AS rn
    FROM cohort
    WHERE has_icu = 1
  ) WHERE rn = 1
),
readmissions AS (
  -- Flag 30-day readmissions
  SELECT 
    ia.*,
    CASE 
      WHEN COUNT(r.hadm_id) > 0 THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM index_admissions ia
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` r
    ON ia.subject_id = r.subject_id
    AND r.hadm_id != ia.index_hadm_id
    AND r.admittime >= ia.index_dischtime
    AND r.admittime < TIMESTAMP_ADD(ia.index_dischtime, INTERVAL 30 DAY)
    AND r.hospital_expire_flag = 0  -- Exclude death as readmission
  GROUP BY 
    ia.subject_id, ia.index_hadm_id, ia.index_admittime, ia.index_dischtime, ia.index_los_days
)
-- Aggregations
SELECT 
  -- 30-day readmission rate
  SAFE_DIVIDE(SUM(readmitted_30d), COUNT(DISTINCT index_hadm_id)) AS readmission_rate_30d,
  
  -- Median index LOS by readmission status
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN index_los_days END, 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN index_los_days END, 2)[OFFSET(1)] AS median_los_not_readmitted,
  
  -- Percent index stays >4 days by readmission status
  SAFE_DIVIDE(SUM(CASE WHEN readmitted_30d = 1 AND index_los_days > 4 THEN 1 ELSE 0 END), SUM(CASE WHEN readmitted_30d = 1 THEN 1 ELSE 0 END)) AS pct_stays_gt4d_readmitted,
  SAFE_DIVIDE(SUM(CASE WHEN readmitted_30d = 0 AND index_los_days > 4 THEN 1 ELSE 0 END), SUM(CASE WHEN readmitted_30d = 0 THEN 1 ELSE 0 END)) AS pct_stays_gt4d_not_readmitted
  
FROM readmissions;
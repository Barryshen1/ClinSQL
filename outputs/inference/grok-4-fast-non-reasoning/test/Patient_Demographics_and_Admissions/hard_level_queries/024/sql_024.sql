WITH cohort AS (
  -- Qualifying index admissions: male, Medicare, age 76-86 at admission, ED admit, principal ischemic stroke, no in-hospital death
  SELECT 
    p.subject_id,
    a.hadm_id AS index_hadm_id,
    a.admittime,
    a.dischtime,
    -- Compute age at admission using anchor_age adjusted by year difference
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS admission_age,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn  -- Earliest qualifying admission per patient
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 76 AND 86  -- Age 76-86 at admission
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.hospital_expire_flag = 0
    AND CAST(d.seq_num AS STRING) = '1'  -- Principal diagnosis
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I63%'  -- Principal ischemic stroke (cerebral infarction)
),
index_cohort AS (
  -- Select only the first qualifying admission per patient
  SELECT subject_id, index_hadm_id, admittime, dischtime
  FROM cohort
  WHERE rn = 1
    AND dischtime IS NOT NULL  -- Exclude if no discharge
),
readmissions AS (
  -- All subsequent admissions within 30 days of index discharge
  SELECT 
    ic.subject_id,
    ic.index_hadm_id,
    ic.admittime AS index_admittime,
    ic.dischtime AS index_dischtime,
    ra.hadm_id AS readm_hadm_id,
    ra.admittime AS readm_admittime,
    ra.dischtime AS readm_dischtime,
    SAFE.DATE_DIFF(ra.admittime, ic.dischtime, DAY) AS days_to_readmit
  FROM index_cohort ic
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ra
    ON ic.subject_id = ra.subject_id
    AND ra.hadm_id != ic.index_hadm_id  -- Exclude same admission
  WHERE ra.admittime > ic.dischtime  -- After index discharge
    AND ra.admittime <= DATE_ADD(ic.dischtime, INTERVAL 30 DAY)  -- Within 30 days
    AND ra.hospital_expire_flag = 0  -- Exclude in-hospital deaths on readmission
    AND ra.dischtime IS NOT NULL  -- Exclude ongoing admissions
),
readmitted_patients AS (
  -- Distinct patients with at least one readmission
  SELECT DISTINCT subject_id
  FROM readmissions
),
los_stats AS (
  -- Compute index LOS and readmission status
  SELECT 
    ic.subject_id,
    ic.index_hadm_id,
    SAFE.DATE_DIFF(ic.dischtime, ic.admittime, DAY) AS index_los,
    CASE WHEN rp.subject_id IS NOT NULL THEN 1 ELSE 0 END AS is_readmitted
  FROM index_cohort ic
  LEFT JOIN readmitted_patients rp
    ON ic.subject_id = rp.subject_id
),
icu_cohort AS (
  -- Index admissions with ICU stays (using icustays for accurate ICU LOS)
  SELECT 
    los.subject_id,
    los.index_hadm_id,
    SUM(SAFE.DATE_DIFF(COALESCE(icu.outtime, los.dischtime), icu.intime, DAY)) AS total_icu_los_days
  FROM los_stats los
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON los.subject_id = icu.subject_id 
    AND los.index_hadm_id = icu.hadm_id
  WHERE icu.los > 0  -- Only admissions with ICU time
  GROUP BY los.subject_id, los.index_hadm_id
),
all_stats AS (
  -- Combine LOS, readmission status, and ICU LOS for full cohort
  SELECT 
    los.subject_id,
    los.index_hadm_id,
    los.index_los,
    los.is_readmitted,
    COALESCE(icu.total_icu_los_days, 0) AS total_icu_los_days,
    CASE WHEN COALESCE(icu.total_icu_los_days, 0) > 5 THEN 1 ELSE 0 END AS stay_gt_5_days
  FROM los_stats los
  LEFT JOIN icu_cohort icu
    ON los.subject_id = icu.subject_id AND los.index_hadm_id = icu.index_hadm_id
)

-- Final aggregations
SELECT 
  -- 30-day all-cause readmission rate (%)
  (COUNT(DISTINCT CASE WHEN is_readmitted = 1 THEN subject_id END) * 100.0 / COUNT(DISTINCT subject_id)) AS readmission_rate_pct,
  
  -- Median index LOS for readmitted
  (SELECT APPROX_QUANTILES(index_los, 2)[OFFSET(1)] FROM all_stats WHERE is_readmitted = 1) AS median_los_readmitted,
  
  -- Median index LOS for non-readmitted
  (SELECT APPROX_QUANTILES(index_los, 2)[OFFSET(1)] FROM all_stats WHERE is_readmitted = 0) AS median_los_non_readmitted,
  
  -- Percent index stays >5 days (among those with ICU stays)
  (COUNT(DISTINCT CASE WHEN stay_gt_5_days = 1 THEN subject_id END) * 100.0 / COUNT(DISTINCT CASE WHEN total_icu_los_days > 0 THEN subject_id END)) AS pct_icu_stays_gt_5_days

FROM all_stats;
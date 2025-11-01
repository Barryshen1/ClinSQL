WITH asthma_cohort AS (
  SELECT DISTINCT 
    a.hadm_id, 
    a.subject_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND LOWER(d_icd.long_title) LIKE '%asthma%'
    AND LOWER(d_icd.long_title) LIKE '%exacerbation%'
),

lab_events_first_48h AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN asthma_cohort ac ON l.hadm_id = ac.hadm_id
  WHERE l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND l.charttime >= ac.admittime
    AND l.charttime <= ac.admittime + INTERVAL 48 HOUR
),

critical_lab_events_astro AS (
  SELECT 
    hadm_id,
    COUNT(*) AS critical_lab_count
  FROM lab_events_first_48h
  WHERE valuenum < ref_range_lower OR valuenum > ref_range_upper
  GROUP BY hadm_id
),

critical_lab_events_all AS (
  SELECT 
    l.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON l.hadm_id = a.hadm_id
  WHERE l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND l.charttime >= a.admittime
    AND l.charttime <= a.admittime + INTERVAL 48 HOUR
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY l.hadm_id
),

asthma_stats AS (
  SELECT 
    PERCENTILE_CONT(critical_lab_count, 0.75) AS asthma_75th_percentile,
    PERCENTILE_CONT(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0, 0.5) AS median_los_days,
    AVG(hospital_expire_flag) AS in_hospital_mortality_rate
  FROM asthma_cohort ac
  LEFT JOIN critical_lab_events_astro clea ON ac.hadm_id = clea.hadm_id
),

all_inpatients_stats AS (
  SELECT 
    PERCENTILE_CONT(critical_lab_count, 0.75) AS all_inpatients_75th_percentile
  FROM critical_lab_events_all
)

SELECT 
  (SELECT asthma_75th_percentile FROM asthma_stats) AS asthma_75th_percentile,
  (SELECT all_inpatients_75th_percentile FROM all_inpatients_stats) AS all_inpatients_75th_percentile,
  (SELECT median_los_days FROM asthma_stats) AS median_los_days,
  (SELECT in_hospital_mortality_rate FROM asthma_stats) AS in_hospital_mortality_rate;
WITH asthma_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'asthma.*exacerbation')
),
cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    (EXTRACT(YEAR FROM adm.admittime) - (pt.anchor_year - pt.anchor_age)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
  INNER JOIN asthma_codes 
    ON diag.icd_code = asthma_codes.icd_code 
    AND diag.icd_version = asthma_codes.icd_version
  WHERE 
    pt.gender = 'M' 
    AND (EXTRACT(YEAR FROM adm.admittime) - (pt.anchor_year - pt.anchor_age)) BETWEEN 52 AND 62
),
lab_events AS (
  SELECT
    c.hadm_id,
    COUNT(l.labevent_id) AS lab_instability_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.flag IS NOT NULL AND l.flag != 'normal'
  GROUP BY c.hadm_id
),
cohort_with_scores AS (
  SELECT
    c.*,
    COALESCE(l.lab_instability_score, 0) AS lab_instability_score
  FROM cohort c
  LEFT JOIN lab_events l
    ON c.hadm_id = l.hadm_id
),
percentile AS (
  SELECT 
    APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(90)] AS p90_score
  FROM cohort_with_scores
)
SELECT 
  'Entire Cohort' AS group_name,
  COUNT(*) AS n_patients,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(los) AS mean_los_days,
  AVG(lab_instability_score) AS avg_critical_lab_events
FROM cohort_with_scores
UNION ALL
SELECT 
  'Top Decile' AS group_name,
  COUNT(*) AS n_patients,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(los) AS mean_los_days,
  AVG(lab_instability_score) AS avg_critical_lab_events
FROM cohort_with_scores
CROSS JOIN percentile
WHERE lab_instability_score >= p90_score;
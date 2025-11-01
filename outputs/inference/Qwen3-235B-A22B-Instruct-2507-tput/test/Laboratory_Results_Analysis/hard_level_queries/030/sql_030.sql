WITH asthma_cohort AS (
  SELECT DISTINCT a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
    ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND LOWER(d_diag.long_title) LIKE '%asthma%'
    AND LOWER(d_diag.long_title) LIKE '%exacerbation%'
),
abnormal_labs_48h AS (
  SELECT 
    ac.hadm_id,
    COUNT(*) AS abnormal_lab_count
  FROM asthma_cohort ac
  JOIN `physionet-data.mimiciv_3_1_hosp`.labevents l
    ON ac.hadm_id = l.hadm_id
  WHERE l.charttime >= ac.admittime
    AND l.charttime <= DATETIME_ADD(ac.admittime, INTERVAL 48 HOUR)
    AND LOWER(l.flag) = 'abnormal'
  GROUP BY ac.hadm_id
),
cohort_stats AS (
  SELECT
    APPROX_QUANTILES(COALESCE(abnormal_lab_count, 0), 100)[OFFSET(75)] AS lab_instability_score_75th_percentile,
    AVG(DATETIME_DIFF(ac.dischtime, ac.admittime, SECOND) / (24*60*60)) AS avg_hospital_los_days,
    AVG(ac.hospital_expire_flag) AS in_hospital_mortality_rate
  FROM asthma_cohort ac
  LEFT JOIN abnormal_labs_48h alb ON ac.hadm_id = alb.hadm_id
)
SELECT
  lab_instability_score_75th_percentile,
  avg_hospital_los_days,
  in_hospital_mortality_rate
FROM cohort_stats;
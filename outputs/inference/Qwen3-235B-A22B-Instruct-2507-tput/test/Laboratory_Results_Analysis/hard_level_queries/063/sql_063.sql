WITH patients_with_pe AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 53 AND 63
    AND LOWER(d.long_title) LIKE '%pulmonary embolism%'
),
abnormal_labs_72h AS (
  SELECT 
    pwp.subject_id,
    pwp.hadm_id,
    COUNT(*) AS abnormal_lab_count
  FROM patients_with_pe pwp
  JOIN `physionet-data.mimiciv_3_1_hosp`.labevents l ON pwp.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems d ON l.itemid = d.itemid
  WHERE l.charttime >= pwp.admittime 
    AND l.charttime <= DATETIME_ADD(pwp.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND (
      LOWER(l.flag) = 'abnormal'
      OR (l.valuenum < l.ref_range_lower AND l.ref_range_lower IS NOT NULL)
      OR (l.valuenum > l.ref_range_upper AND l.ref_range_upper IS NOT NULL)
    )
  GROUP BY pwp.subject_id, pwp.hadm_id
),
percentiles AS (
  SELECT 
    APPROX_QUANTILES(abnormal_lab_count, 100)[OFFSET(75)] AS p75_score
  FROM abnormal_labs_72h
),
high_instability AS (
  SELECT pwp.subject_id, pwp.hadm_id, pwp.admittime, pwp.dischtime, pwp.hospital_expire_flag, al.abnormal_lab_count
  FROM patients_with_pe pwp
  JOIN abnormal_labs_72h al ON pwp.hadm_id = al.hadm_id
  CROSS JOIN percentiles
  WHERE al.abnormal_lab_count >= p75_score
)
SELECT
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100 AS mortality_rate_percent,
  AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / 86400.0) AS mean_los_days,
  AVG(abnormal_lab_count) AS mean_critical_lab_rate
FROM high_instability;
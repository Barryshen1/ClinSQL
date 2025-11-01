WITH patients_age AS (
  SELECT
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 65 AND 75
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
),
pancreatitis_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = 10
    AND di.icd_code LIKE 'K85%'
),
cohort AS (
  SELECT
    pa.*,
    CASE WHEN pd.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_pancreatitis
  FROM patients_age pa
  LEFT JOIN pancreatitis_diagnoses pd
    ON pa.hadm_id = pd.hadm_id
),
lab_abnormalities AS (
  SELECT
    le.hadm_id,
    COUNT(*) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN patients_age pa
    ON le.hadm_id = pa.hadm_id
  WHERE le.charttime >= pa.admittime
    AND le.charttime <= DATETIME_ADD(pa.admittime, INTERVAL 48 HOUR)
    AND (
      le.flag = 'abnormal'
      OR (
        le.valuenum IS NOT NULL
        AND (
          (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
          OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
      )
    )
  GROUP BY le.hadm_id
),
cohort_with_instability AS (
  SELECT
    c.*,
    COALESCE(lab.instability_score, 0) AS instability_score,
    CASE WHEN COALESCE(lab.instability_score, 0) > 0 THEN 1 ELSE 0 END AS has_critical_lab,
    NTILE(5) OVER (ORDER BY COALESCE(lab.instability_score, 0)) AS quintile
  FROM cohort c
  LEFT JOIN lab_abnormalities lab
    ON c.hadm_id = lab.hadm_id
),
pancreatitis_stratified AS (
  SELECT
    'Pancreatitis' AS group_label,
    quintile,
    COUNT(*) AS count_patients,
    AVG(instability_score) AS mean_instability,
    AVG(los) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(has_critical_lab) AS pct_critical_labs
  FROM cohort_with_instability
  WHERE has_pancreatitis = 1
  GROUP BY quintile
),
control_group AS (
  SELECT
    'Control' AS group_label,
    NULL AS quintile,
    COUNT(*) AS count_patients,
    AVG(instability_score) AS mean_instability,
    AVG(los) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(has_critical_lab) AS pct_critical_labs
  FROM cohort_with_instability
  WHERE has_pancreatitis = 0
)
SELECT
  group_label,
  quintile,
  count_patients,
  mean_instability,
  mean_los,
  mortality_rate,
  pct_critical_labs
FROM pancreatitis_stratified
UNION ALL
SELECT
  group_label,
  quintile,
  count_patients,
  mean_instability,
  mean_los,
  mortality_rate,
  pct_critical_labs
FROM control_group
ORDER BY group_label DESC, quintile;
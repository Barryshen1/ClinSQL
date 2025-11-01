WITH dvt_icd_codes AS (
  -- DVT ICD-9: 453.x, ICD-10: I82.x
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^453'))
     OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I82'))
),
dvt_admissions AS (
  -- Male, age 42-52, with DVT
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN dvt_icd_codes dvt
    ON dx.icd_code = dvt.icd_code AND dx.icd_version = dvt.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 42 AND 52
),
lab_instability AS (
  -- For each DVT admission, count abnormal labs in first 72h
  SELECT
    dvt.subject_id,
    dvt.hadm_id,
    COUNTIF(
      (le.flag = 'abnormal')
      OR (le.flag = 'critical')
      OR (
        SAFE_CAST(le.valuenum AS FLOAT64) IS NOT NULL
        AND (
          (SAFE_CAST(le.ref_range_lower AS FLOAT64) IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) < SAFE_CAST(le.ref_range_lower AS FLOAT64))
          OR
          (SAFE_CAST(le.ref_range_upper AS FLOAT64) IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) > SAFE_CAST(le.ref_range_upper AS FLOAT64))
        )
      )
    ) AS instability_score,
    COUNTIF(le.flag = 'critical') AS critical_lab_count,
    COUNT(*) AS total_lab_count
  FROM dvt_admissions dvt
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON dvt.hadm_id = le.hadm_id
  WHERE le.charttime BETWEEN dvt.admittime AND TIMESTAMP_ADD(dvt.admittime, INTERVAL 72 HOUR)
  GROUP BY dvt.subject_id, dvt.hadm_id
),
percentile_95 AS (
  -- Calculate 95th percentile of instability score
  SELECT
    PERCENTILE_CONT(instability_score, 0.95) OVER () AS instability_score_95th
  FROM lab_instability
  LIMIT 1
),
high_instability_patients AS (
  -- Patients at or above 95th percentile
  SELECT
    li.subject_id,
    li.hadm_id,
    li.instability_score,
    li.critical_lab_count,
    li.total_lab_count,
    da.anchor_age,
    da.gender,
    da.admittime,
    da.dischtime,
    da.hospital_expire_flag,
    TIMESTAMP_DIFF(da.dischtime, da.admittime, HOUR)/24.0 AS los_days
  FROM lab_instability li
  JOIN dvt_admissions da
    ON li.hadm_id = da.hadm_id
  CROSS JOIN percentile_95 p95
  WHERE li.instability_score >= p95.instability_score_95th
),
high_instability_summary AS (
  SELECT
    COUNT(*) AS n_patients,
    SUM(CAST(hospital_expire_flag AS INT64)) AS n_deaths,
    AVG(los_days) AS mean_los,
    SUM(critical_lab_count) / SUM(total_lab_count) AS critical_lab_rate
  FROM high_instability_patients
),
all_inpatients_lab_critical AS (
  -- All inpatients: critical lab rate in first 72h
  SELECT
    SUM(CASE WHEN le.flag = 'critical' THEN 1 ELSE 0 END) AS critical_lab_count,
    COUNT(*) AS total_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON adm.hadm_id = le.hadm_id
  WHERE le.charttime BETWEEN adm.admittime AND TIMESTAMP_ADD(adm.admittime, INTERVAL 72 HOUR)
),
all_inpatients_critical_rate AS (
  SELECT
    critical_lab_count / total_lab_count AS critical_lab_rate
  FROM all_inpatients_lab_critical
)
-- Final output
SELECT
  (SELECT instability_score_95th FROM percentile_95) AS instability_score_95th,
  hs.n_patients AS n_patients_95th_percentile,
  hs.n_deaths AS deaths_95th_percentile,
  hs.mean_los AS mean_los_95th_percentile,
  hs.critical_lab_rate AS critical_lab_rate_95th_percentile,
  aicr.critical_lab_rate AS critical_lab_rate_all_inpatients
FROM high_instability_summary hs
CROSS JOIN all_inpatients_critical_rate aicr;
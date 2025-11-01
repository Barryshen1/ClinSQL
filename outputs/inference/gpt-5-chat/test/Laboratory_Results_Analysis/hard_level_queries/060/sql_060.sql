WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END AS is_icu
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 52 AND 62
    AND (
         (diag.icd_version = 9 AND diag.icd_code = '4275')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I46%')
    )
),
instability AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.is_icu,
    COUNTIF(LOWER(lab.flag) LIKE 'abnormal%') AS instability_score,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR)/24.0 AS los_days,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON c.hadm_id = lab.hadm_id
    AND lab.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.is_icu, c.admittime, c.dischtime, c.hospital_expire_flag
),
stats AS (
  SELECT
    CASE WHEN is_icu = 1 THEN 'Critical care' ELSE 'General inpatient' END AS cohort_type,
    COUNT(*) OVER (PARTITION BY is_icu) AS n_admissions,
    PERCENTILE_CONT(instability_score, 0.25) OVER (PARTITION BY is_icu) AS instability_q1,
    PERCENTILE_CONT(instability_score, 0.5) OVER (PARTITION BY is_icu) AS instability_median,
    AVG(los_days) OVER (PARTITION BY is_icu) AS avg_los_days,
    AVG(hospital_expire_flag) OVER (PARTITION BY is_icu) AS mortality_rate
  FROM instability
)
SELECT DISTINCT
  cohort_type,
  n_admissions,
  instability_q1,
  instability_median,
  avg_los_days,
  mortality_rate
FROM stats
ORDER BY cohort_type DESC;
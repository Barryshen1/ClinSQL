WITH pneumonia_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-9: 480-486
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^48[0-6]$'))
    -- ICD-10: J12-J18
    OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^J1[2-8]'))
),

-- Cohort: male, age 60-70, primary pneumonia
cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN pneumonia_icd icd
    ON diag.icd_code = icd.icd_code AND diag.icd_version = icd.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 60 AND 70
    AND diag.seq_num = 1
),

-- 72-hour lab instability score per admission
lab_instability AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNTIF(lab.flag = 'abnormal'
      AND lab.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    ) AS instability_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON c.hadm_id = lab.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),

-- ICU stays per admission (critical-event frequency)
icu_freq_cohort AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT icu.stay_id) AS icu_stays
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON c.hadm_id = icu.hadm_id
  GROUP BY c.hadm_id
),

icu_freq_all AS (
  SELECT
    adm.hadm_id,
    COUNT(DISTINCT icu.stay_id) AS icu_stays
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  GROUP BY adm.hadm_id
),

-- Cohort LOS and mortality
cohort_stats AS (
  SELECT
    COUNT(*) AS n_admissions,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0) AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM cohort
)

-- Final output
SELECT
  -- Part 1: 75th percentile of instability score
  (
    SELECT APPROX_QUANTILES(instability_score, 4)[3]
    FROM lab_instability
  ) AS instability_score_75th_percentile,

  -- Part 2: Mean critical-event frequency (ICU stays/admission)
  (
    SELECT AVG(icu_stays)
    FROM icu_freq_cohort
  ) AS mean_icu_stays_per_admission_cohort,

  (
    SELECT AVG(icu_stays)
    FROM icu_freq_all
  ) AS mean_icu_stays_per_admission_all_inpatients,

  -- Cohort LOS and mortality
  cs.mean_los_days,
  cs.mortality_rate,
  cs.n_admissions
FROM cohort_stats cs;
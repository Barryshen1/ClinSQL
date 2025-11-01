WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.gender, p.anchor_age, p.dod,
         a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND (
         (d.icd_version = 10 AND d.icd_code = 'R65.21') -- ICD-10 septic shock
         OR (d.icd_version = 9 AND d.icd_code = '78552') -- ICD-9 septic shock without dot
         OR (d.icd_version = 9 AND d.icd_code = '785.52') -- ICD-9 septic shock with dot
        )
),
vitals AS (
  SELECT ce.subject_id, ce.hadm_id, ce.charttime,
         -- flags for abnormal
         MAX(CASE WHEN di.label LIKE 'Heart Rate%' AND ce.valuenum > 120 THEN 1 ELSE 0 END) AS hr_abn,
         MAX(CASE WHEN di.label LIKE 'SysBP%' AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS sbp_abn,
         MAX(CASE WHEN di.label LIKE 'Respiratory Rate%' AND ce.valuenum > 24 THEN 1 ELSE 0 END) AS rr_abn,
         MAX(CASE WHEN di.label LIKE 'SpO2%' AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS spo2_abn,
         MAX(CASE WHEN di.label LIKE 'Temperature%' AND (ce.valuenum < 36 OR ce.valuenum > 38) THEN 1 ELSE 0 END) AS temp_abn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN cohort c
    ON ce.subject_id = c.subject_id
   AND ce.hadm_id = c.hadm_id
  WHERE DATETIME_DIFF(ce.charttime, c.admittime, HOUR) BETWEEN 0 AND 48
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.subject_id, ce.hadm_id, ce.charttime
),
instability_scores AS (
  SELECT subject_id, hadm_id, charttime,
         (hr_abn + sbp_abn + rr_abn + spo2_abn + temp_abn) AS instability_score
  FROM vitals
),
score_stats AS (
  SELECT
    APPROX_QUANTILES(instability_score, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(instability_score, 4)[OFFSET(2)] AS median,
    APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS q3,
    (APPROX_QUANTILES(instability_score, 4)[OFFSET(3)]
     - APPROX_QUANTILES(instability_score, 4)[OFFSET(1)]) AS iqr
  FROM instability_scores
),
lab_all AS (
  SELECT subject_id, hadm_id,
         COUNTIF(flag IS NOT NULL AND flag != '') AS abnormal_lab_count,
         COUNT(*) AS total_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY subject_id, hadm_id
),
lab_cohort AS (
  SELECT la.subject_id, la.hadm_id,
         abnormal_lab_count, total_lab_count
  FROM lab_all la
  JOIN cohort c
    ON la.subject_id = c.subject_id AND la.hadm_id = c.hadm_id
),
lab_freqs AS (
  SELECT
    SAFE_DIVIDE(SUM(abnormal_lab_count), SUM(total_lab_count)) AS cohort_abn_lab_freq
  FROM lab_cohort
),
lab_freqs_general AS (
  SELECT
    SAFE_DIVIDE(SUM(abnormal_lab_count), SUM(total_lab_count)) AS general_abn_lab_freq
  FROM lab_all
),
cohort_outcomes AS (
  SELECT
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    COUNT(*) AS total_cohort,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_rate
  FROM cohort
)
SELECT
  ss.q1, ss.median, ss.q3, ss.iqr,
  lf.cohort_abn_lab_freq,
  lg.general_abn_lab_freq,
  co.avg_los_days,
  co.mortality_rate,
  co.total_cohort, co.deaths
FROM score_stats ss
CROSS JOIN lab_freqs lf
CROSS JOIN lab_freqs_general lg
CROSS JOIN cohort_outcomes co;
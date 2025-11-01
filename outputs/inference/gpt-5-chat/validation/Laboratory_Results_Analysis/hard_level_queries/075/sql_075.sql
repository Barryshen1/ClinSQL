WITH dvt_hadm AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddd
    ON diag.icd_code = ddd.icd_code
    AND diag.icd_version = ddd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 42 AND 52
    AND LOWER(ddd.long_title) LIKE '%deep vein thromb%'
),
lab_scores AS (
  SELECT
    dv.subject_id,
    dv.hadm_id,
    COUNTIF(le.flag IS NOT NULL) AS instability_score,
    COUNT(*) AS total_labs,
    SUM(CASE WHEN le.flag IS NOT NULL THEN 1 ELSE 0 END) AS abnormal_labs
  FROM dvt_hadm dv
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON dv.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON dv.hadm_id = adm.hadm_id
  WHERE le.charttime BETWEEN adm.admittime AND TIMESTAMP_ADD(adm.admittime, INTERVAL 72 HOUR)
  GROUP BY dv.subject_id, dv.hadm_id
),
score_threshold AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.95) OVER() AS p95_score
  FROM lab_scores
  LIMIT 1
),
high_group AS (
  SELECT ls.*, st.p95_score
  FROM lab_scores ls
  CROSS JOIN score_threshold st
  WHERE ls.instability_score >= st.p95_score
),
mort_los AS (
  SELECT
    hg.p95_score,
    COUNT(*) AS n_high,
    AVG(a.hospital_expire_flag) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0) AS mean_los_days,
    AVG(hg.abnormal_labs / NULLIF(hg.total_labs,0)) AS critical_lab_rate_high
  FROM high_group hg
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON hg.hadm_id = a.hadm_id
  GROUP BY hg.p95_score
),
overall_rates AS (
  SELECT
    AVG(abnormal_labs / NULLIF(total_labs,0)) AS critical_lab_rate_overall
  FROM lab_scores
)
SELECT
  m.p95_score,
  m.n_high,
  m.mortality_rate,
  m.mean_los_days,
  m.critical_lab_rate_high,
  o.critical_lab_rate_overall
FROM mort_los m
CROSS JOIN overall_rates o;
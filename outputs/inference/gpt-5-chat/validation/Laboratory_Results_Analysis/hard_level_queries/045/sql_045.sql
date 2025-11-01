WITH asthma_cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.gender, p.anchor_age,
         a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND LOWER(dd.long_title) LIKE '%asthma%'
    AND LOWER(dd.long_title) LIKE '%exacerbation%'
),
asthma_lab_scores AS (
  SELECT c.subject_id, c.hadm_id,
         COUNT(*) AS lab_instability_score
  FROM asthma_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
   AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
   AND le.flag IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id
),
pct_threshold AS (
  SELECT APPROX_QUANTILES(lab_instability_score, 10)[OFFSET(9)] AS p90_score
  FROM asthma_lab_scores
),
top_decile AS (
  SELECT c.*, ls.lab_instability_score
  FROM asthma_cohort c
  JOIN asthma_lab_scores ls
    ON c.hadm_id = ls.hadm_id
  JOIN pct_threshold t
    ON ls.lab_instability_score >= t.p90_score
),
top_decile_stats AS (
  SELECT 
    COUNT(*) AS num_cases,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS num_deaths,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0) AS mean_los_days,
    AVG(lab_instability_score) AS avg_lab_instability_score
  FROM top_decile
),
baseline_cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.gender, p.anchor_age,
         a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),
baseline_lab_scores AS (
  SELECT b.subject_id, b.hadm_id,
         COUNT(*) AS lab_instability_score
  FROM baseline_cohort b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON b.hadm_id = le.hadm_id
   AND le.charttime BETWEEN b.admittime AND TIMESTAMP_ADD(b.admittime, INTERVAL 72 HOUR)
   AND le.flag IS NOT NULL
  GROUP BY b.subject_id, b.hadm_id
),
baseline_stats AS (
  SELECT 
    COUNT(*) AS num_cases,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS num_deaths,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0) AS mean_los_days,
    AVG(lab_instability_score) AS avg_lab_instability_score
  FROM baseline_cohort bc
  JOIN baseline_lab_scores bls
    ON bc.hadm_id = bls.hadm_id
)
SELECT 
  'Top Decile Asthma Exacerbation' AS group_label, 
  td.num_cases,
  td.num_deaths,
  td.mean_los_days,
  td.avg_lab_instability_score
FROM top_decile_stats td

UNION ALL

SELECT 
  'Age-matched Male Baseline' AS group_label,
  bs.num_cases,
  bs.num_deaths,
  bs.mean_los_days,
  bs.avg_lab_instability_score
FROM baseline_stats bs;
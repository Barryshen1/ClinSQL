WITH cohort AS (
  -- All eligible female inpatients, age 53-63, label ACS vs Control
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los_days,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE d.hadm_id = a.hadm_id
          AND (
            LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
            OR LOWER(dd.long_title) LIKE '%angina%'
            OR LOWER(dd.long_title) LIKE '%acute coronary%'
          )
      ) THEN 'ACS'
      ELSE 'Control'
    END AS cohort_type
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),
lab_crit AS (
  -- Critical labs in first 72 hours by category
  SELECT
    l.subject_id,
    l.hadm_id,
    dl.category
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  JOIN cohort c
    ON l.hadm_id = c.hadm_id
  WHERE l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.flag IS NOT NULL -- marks abnormal/critical
    AND dl.category IS NOT NULL
  GROUP BY l.subject_id, l.hadm_id, dl.category
),
score AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.cohort_type,
    c.hospital_expire_flag,
    c.los_days,
    COUNT(DISTINCT lc.category) AS instability_score
  FROM cohort c
  LEFT JOIN lab_crit lc
    ON c.subject_id = lc.subject_id AND c.hadm_id = lc.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.cohort_type, c.hospital_expire_flag, c.los_days
),
acs_quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag,
    los_days,
    instability_score,
    NTILE(4) OVER (ORDER BY instability_score) AS score_quartile
  FROM score
  WHERE cohort_type = 'ACS'
),
quartile_stats AS (
  SELECT
    score_quartile,
    COUNT(*) AS n_patients,
    100.0 * SUM(hospital_expire_flag)/COUNT(*) AS mortality_percent,
    AVG(los_days) AS avg_los_days
  FROM acs_quartiles
  GROUP BY score_quartile
),
control_vs_acs AS (
  SELECT
    cohort_type,
    AVG(instability_score) AS avg_instability_score
  FROM score
  GROUP BY cohort_type
)
-- Final output: quartile outcome table plus average score by cohort
SELECT 'QUARTILE_STATS' AS result_type, CAST(score_quartile AS STRING) AS grp,
       n_patients, mortality_percent, avg_los_days
FROM quartile_stats
UNION ALL
SELECT 'COHORT_AVG_SCORE', cohort_type, NULL, avg_instability_score, NULL
FROM control_vs_acs
ORDER BY result_type, grp;
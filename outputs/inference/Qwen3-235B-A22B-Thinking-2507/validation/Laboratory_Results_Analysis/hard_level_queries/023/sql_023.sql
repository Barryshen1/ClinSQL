WITH admissions_with_age AS (
  SELECT 
    a.*,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),

ami_cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM admissions_with_age a
  WHERE a.gender = 'F'
    AND a.age_at_admission BETWEEN 90 AND 100
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '410%')
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
        )
    )
),

lab_instability_scores AS (
  SELECT
    a.hadm_id,
    COUNT(*) AS lab_instability_score
  FROM ami_cohort a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
    AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
    AND l.flag IS NOT NULL
    AND LOWER(l.flag) LIKE '%critical%'
  GROUP BY a.hadm_id
),

p75_value AS (
  SELECT 
    APPROX_QUANTILES(lab_instability_score, 1000)[OFFSET(750)] AS p75
  FROM lab_instability_scores
),

high_group AS (
  SELECT a.*
  FROM ami_cohort a
  INNER JOIN lab_instability_scores l
    ON a.hadm_id = l.hadm_id
  CROSS JOIN p75_value p
  WHERE l.lab_instability_score >= p.p75
),

all_90_100 AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM admissions_with_age a
  WHERE a.age_at_admission BETWEEN 90 AND 100
),

high_group_metrics AS (
  SELECT
    'high_group' AS group_name,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los,
    AVG(CASE WHEN has_critical_lab = 1 THEN 1 ELSE 0 END) AS critical_lab_rate
  FROM (
    SELECT 
      a.hadm_id,
      a.hospital_expire_flag,
      a.admittime,
      a.dischtime,
      MAX(CASE WHEN l.flag IS NOT NULL AND LOWER(l.flag) LIKE '%critical%' THEN 1 ELSE 0 END) AS has_critical_lab
    FROM high_group a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.hadm_id = l.hadm_id
      AND l.charttime BETWEEN a.admittime AND a.dischtime
    GROUP BY a.hadm_id, a.hospital_expire_flag, a.admittime, a.dischtime
  )
),

all_90_100_metrics AS (
  SELECT
    'all_90_100' AS group_name,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los,
    AVG(CASE WHEN has_critical_lab = 1 THEN 1 ELSE 0 END) AS critical_lab_rate
  FROM (
    SELECT 
      a.hadm_id,
      a.hospital_expire_flag,
      a.admittime,
      a.dischtime,
      MAX(CASE WHEN l.flag IS NOT NULL AND LOWER(l.flag) LIKE '%critical%' THEN 1 ELSE 0 END) AS has_critical_lab
    FROM all_90_100 a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.hadm_id = l.hadm_id
      AND l.charttime BETWEEN a.admittime AND a.dischtime
    GROUP BY a.hadm_id, a.hospital_expire_flag, a.admittime, a.dischtime
  )
)

SELECT * FROM high_group_metrics
UNION ALL
SELECT * FROM all_90_100_metrics;
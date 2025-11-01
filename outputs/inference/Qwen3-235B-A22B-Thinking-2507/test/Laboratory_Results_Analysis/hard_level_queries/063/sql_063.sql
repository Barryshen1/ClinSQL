WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.dischtime IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 53 AND 63
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('41511', '41512', '41513', '41519'))
          OR
          (d.icd_version = 10 AND d.icd_code IN ('I260', 'I2601', 'I2602', 'I2609', 'I269', 'I2690', 'I2691', 'I2692', 'I2699'))
        )
    )
),

lab_score AS (
  SELECT 
    c.hadm_id,
    COUNT(l.labevent_id) AS lab_instability_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime >= c.admittime
    AND l.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.flag = 'abnormal'
  GROUP BY c.hadm_id
),

threshold AS (
  SELECT 
    APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(75)] AS threshold
  FROM lab_score
),

combined AS (
  SELECT 
    c.*,
    ls.lab_instability_score
  FROM cohort c
  INNER JOIN lab_score ls 
    ON c.hadm_id = ls.hadm_id
)

SELECT 
  AVG(CASE WHEN lab_instability_score >= t.threshold THEN hospital_expire_flag ELSE NULL END) * 100 AS mortality_pct,
  AVG(CASE WHEN lab_instability_score >= t.threshold THEN DATETIME_DIFF(dischtime, admittime, SECOND) / (60*60*24) ELSE NULL END) AS mean_los_days,
  AVG(CASE WHEN lab_instability_score >= t.threshold THEN lab_instability_score ELSE NULL END) AS critical_lab_rate_high,
  AVG(CASE WHEN lab_instability_score < t.threshold THEN lab_instability_score ELSE NULL END) AS critical_lab_rate_low
FROM combined, threshold t;
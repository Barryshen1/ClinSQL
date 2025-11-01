WITH female_ami_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.los,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 90 AND 100
    AND d.icd_code LIKE 'I21%'
),

lab_scores AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    COUNT(l.labevent_id) AS lab_score
  FROM female_ami_cohort f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON f.hadm_id = l.hadm_id
    AND l.charttime BETWEEN f.admittime AND f.admittime + INTERVAL 48 HOUR
    AND l.flag IS NOT NULL
  GROUP BY f.subject_id, f.hadm_id
),

percentile AS (
  SELECT
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY lab_score) AS p75
  FROM lab_scores
),

high_score_patients AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.hospital_expire_flag,
    f.los,
    ls.lab_score
  FROM female_ami_cohort f
  JOIN lab_scores ls
    ON f.subject_id = ls.subject_id AND f.hadm_id = ls.hadm_id
  CROSS JOIN percentile p
  WHERE ls.lab_score >= p.p75
),

all_90_100_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.los,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 90 AND 100
),

all_lab_scores AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(l.labevent_id) AS lab_score
  FROM all_90_100_cohort a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
    AND l.charttime BETWEEN a.admittime AND a.admittime + INTERVAL 48 HOUR
    AND l.flag IS NOT NULL
  GROUP BY a.subject_id, a.hadm_id
),

all_metrics AS (
  SELECT
    AVG(a.hospital_expire_flag) AS mortality_rate,
    AVG(a.los) AS mean_los,
    AVG(CASE WHEN ls.lab_score >= 1 THEN 1 ELSE 0 END) AS critical_lab_rate
  FROM all_90_100_cohort a
  JOIN all_lab_scores ls
    ON a.subject_id = ls.subject_id AND a.hadm_id = ls.hadm_id
)

SELECT
  'High Lab Score (≥75th Percentile)' AS group_name,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(los) AS mean_los,
  AVG(CASE WHEN lab_score >= 1 THEN 1 ELSE 0 END) AS critical_lab_rate
FROM high_score_patients

UNION ALL

SELECT
  'All 90-100 Inpatients' AS group_name,
  mortality_rate,
  mean_los,
  critical_lab_rate
FROM all_metrics;
WITH acs_female_40_50 AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.anchor_age, p.gender,
    a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      (d.icd_version = 9 AND (
          d.icd_code LIKE '410%' OR
          d.icd_code LIKE '411%'))
      OR
      (d.icd_version = 10 AND (
          d.icd_code LIKE 'I20.0%' OR
          d.icd_code LIKE 'I21%' OR
          d.icd_code LIKE 'I22%'))
    )
),
instability_scores AS (
  SELECT
    af.subject_id,
    af.hadm_id,
    COUNTIF(le.flag = 'abnormal') AS instability_score
  FROM acs_female_40_50 af
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON af.subject_id = le.subject_id
    AND af.hadm_id = le.hadm_id
    AND le.charttime >= af.admittime
    AND le.charttime < DATETIME_ADD(af.admittime, INTERVAL 48 HOUR)
  GROUP BY af.subject_id, af.hadm_id
),
score_percentile AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
  FROM instability_scores
),
high_instability_acs AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.instability_score,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM instability_scores s
  JOIN acs_female_40_50 a
    ON s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
  CROSS JOIN score_percentile p
  WHERE s.instability_score >= p.p90_score
),
all_labs AS (
  SELECT
    hadm_id,
    COUNT(*) AS total_labs,
    COUNTIF(flag = 'abnormal') AS abnormal_labs
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY hadm_id
),
metrics_high AS (
  SELECT
    'High Instability ACS' AS group_name,
    AVG(CAST(h.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(DATETIME_DIFF(h.dischtime, h.admittime, DAY)) AS mean_los_days,
    AVG(CAST(al.abnormal_labs AS FLOAT64) / NULLIF(al.total_labs,0)) AS abnormal_lab_rate
  FROM high_instability_acs h
  LEFT JOIN all_labs al
    ON h.hadm_id = al.hadm_id
),
metrics_all AS (
  SELECT
    'All Inpatients' AS group_name,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS mean_los_days,
    AVG(CAST(al.abnormal_labs AS FLOAT64) / NULLIF(al.total_labs,0)) AS abnormal_lab_rate
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  LEFT JOIN all_labs al
    ON adm.hadm_id = al.hadm_id
)
SELECT * FROM metrics_high
UNION ALL
SELECT * FROM metrics_all;
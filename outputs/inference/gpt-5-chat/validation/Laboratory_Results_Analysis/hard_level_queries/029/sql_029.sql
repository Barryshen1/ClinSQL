WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
),
hhs_dx AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
      -- ICD-9 codes for HHS
      (d.icd_version = 9 AND d.icd_code LIKE '250.2%')
      OR
      -- ICD-10 codes for diabetes with hyperosmolarity
      (d.icd_version = 10 AND (
          d.icd_code LIKE 'E10.0%' OR
          d.icd_code LIKE 'E11.0%' OR
          d.icd_code LIKE 'E13.0%'
      ))
    )
),
labs_48h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNTIF(le.flag = 'abnormal') AS abnormal_count,
    COUNT(*) AS total_labs
  FROM cohort c
  JOIN hhs_dx h
    ON c.hadm_id = h.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
  WHERE le.charttime BETWEEN c.admittime 
                         AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),
scored AS (
  SELECT
    c.*,
    l.abnormal_count,
    l.total_labs,
    -- lab instability score = abnormal_count
    l.abnormal_count AS instab_score
  FROM cohort c
  JOIN labs_48h l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
),
threshold AS (
  SELECT PERCENTILE_CONT(instab_score, 0.75) OVER() AS p75
  FROM scored
),
high_group AS (
  SELECT s.*, t.p75
  FROM scored s
  CROSS JOIN (SELECT DISTINCT p75 FROM threshold) t
  WHERE s.instab_score >= t.p75
),
-- General inpatient baseline abnormal rate in first 48h
general_abnormal_rate AS (
  SELECT 
    COUNTIF(le.flag = 'abnormal') / COUNT(*) AS abnormal_rate
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
  WHERE le.charttime BETWEEN a.admittime 
                         AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
)
SELECT
  MAX(hg.p75) AS instability_score_p75,
  AVG(hg.hospital_expire_flag) AS mortality_rate,
  AVG(TIMESTAMP_DIFF(hg.dischtime, hg.admittime, HOUR) / 24.0) AS mean_los_days,
  AVG(hg.abnormal_count / NULLIF(hg.total_labs,0)) AS high_group_abnormal_rate,
  MAX(gar.abnormal_rate) AS general_inpatient_abnormal_rate
FROM high_group hg
CROSS JOIN general_abnormal_rate gar;
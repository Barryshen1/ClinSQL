WITH target_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND d_icd.long_title LIKE '%pulmonary embolism%'
),

lab_instability AS (
  SELECT
    tc.subject_id,
    COUNT(CASE WHEN le.flag IS NOT NULL THEN 1 END) AS lab_instability_score
  FROM target_cohort tc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON tc.subject_id = le.subject_id
    AND le.charttime >= tc.admittime
    AND le.charttime <= TIMESTAMP_ADD(tc.admittime, INTERVAL 72 HOUR)
  GROUP BY tc.subject_id
),

p75 AS (
  SELECT APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(75)] AS p75_score
  FROM lab_instability
),

high_instability AS (
  SELECT
    li.subject_id,
    li.lab_instability_score,
    tc.hospital_expire_flag,
    TIMESTAMP_DIFF(tc.dischtime, tc.admittime, DAY) AS los_days
  FROM lab_instability li
  INNER JOIN target_cohort tc
    ON li.subject_id = tc.subject_id
  CROSS JOIN p75
  WHERE li.lab_instability_score >= p75.p75_score
)

SELECT
  AVG(hi.hospital_expire_flag) * 100 AS mortality_rate_percent,
  AVG(hi.los_days) AS mean_los_days,
  AVG(hi.lab_instability_score) AS mean_abnormal_labs_high_group,
  AVG(li_all.lab_instability_score) AS mean_abnormal_labs_overall_cohort
FROM high_instability hi
CROSS JOIN lab_instability li_all;
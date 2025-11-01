WITH female_ami_90_100 AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
    AND (
      (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
      OR (d.icd_version = 9  AND d.icd_code LIKE '410%')
    )
),
lab_scores AS (
  SELECT f.hadm_id,
    COUNTIF(
      (flag IS NOT NULL AND LOWER(flag) = 'abnormal')
      OR (valuenum IS NOT NULL AND (
            (ref_range_lower IS NOT NULL AND valuenum < ref_range_lower) OR
            (ref_range_upper IS NOT NULL AND valuenum > ref_range_upper)
         ))
    ) AS lab_instability_score,
    COUNT(*) AS total_labs,
    COUNTIF(
      (flag IS NOT NULL AND LOWER(flag) = 'abnormal')
      OR (valuenum IS NOT NULL AND (
            (ref_range_lower IS NOT NULL AND valuenum < ref_range_lower) OR
            (ref_range_upper IS NOT NULL AND valuenum > ref_range_upper)
         ))
    ) / COUNT(*) AS critical_lab_rate
  FROM female_ami_90_100 f
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON f.subject_id = l.subject_id AND f.hadm_id = l.hadm_id
    AND l.charttime BETWEEN f.admittime AND TIMESTAMP_ADD(f.admittime, INTERVAL 48 HOUR)
  GROUP BY f.hadm_id
),
p75_value AS (
  SELECT PERCENTILE_CONT(lab_instability_score, 0.75) OVER () AS p75
  FROM lab_scores
  LIMIT 1
),
female_ami_ge_p75 AS (
  SELECT f.*, ls.lab_instability_score, ls.total_labs, ls.critical_lab_rate
  FROM female_ami_90_100 f
  JOIN lab_scores ls ON f.hadm_id = ls.hadm_id
  CROSS JOIN p75_value pv
  WHERE ls.lab_instability_score >= pv.p75
),
all_inpatients_90_100 AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 90 AND 100
),
all_inp_lab_rates AS (
  SELECT ai.hadm_id,
    COUNTIF(
      (flag IS NOT NULL AND LOWER(flag) = 'abnormal')
      OR (valuenum IS NOT NULL AND (
            (ref_range_lower IS NOT NULL AND valuenum < ref_range_lower) OR
            (ref_range_upper IS NOT NULL AND valuenum > ref_range_upper)
         ))
    ) / COUNT(*) AS critical_lab_rate
  FROM all_inpatients_90_100 ai
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON ai.subject_id = l.subject_id AND ai.hadm_id = l.hadm_id
    AND l.charttime BETWEEN ai.admittime AND TIMESTAMP_ADD(ai.admittime, INTERVAL 48 HOUR)
  GROUP BY ai.hadm_id
)
SELECT 
  'Female AMI ≥P75' AS cohort,
  COUNT(*) AS n_admissions,
  AVG(hospital_expire_flag) AS inhosp_mortality_rate,
  AVG(los_days) AS mean_los_days,
  AVG(critical_lab_rate) AS mean_critical_lab_rate
FROM female_ami_ge_p75
UNION ALL
SELECT 
  'All inpatients 90–100' AS cohort,
  COUNT(*) AS n_admissions,
  AVG(hospital_expire_flag) AS inhosp_mortality_rate,
  AVG(los_days) AS mean_los_days,
  AVG(critical_lab_rate) AS mean_critical_lab_rate
FROM all_inpatients_90_100 ai
JOIN all_inp_lab_rates lr ON ai.hadm_id = lr.hadm_id
;
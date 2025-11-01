WITH 
cohort_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 70 AND 80
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
          OR (d.icd_version = 9 AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%'))
        )
    )
),
cohort_lab_scores AS (
  SELECT 
    ca.hadm_id,
    COUNT(le.labevent_id) AS critical_lab_count
  FROM cohort_admissions ca
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ca.hadm_id = le.hadm_id
    AND le.charttime BETWEEN ca.admittime AND DATETIME_ADD(ca.admittime, INTERVAL 48 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY ca.hadm_id
),
cohort_lab_flag AS (
  SELECT 
    ca.hadm_id,
    MAX(CASE WHEN le.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS has_critical_lab
  FROM cohort_admissions ca
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ca.hadm_id = le.hadm_id
    AND le.charttime BETWEEN ca.admittime AND DATETIME_ADD(ca.admittime, INTERVAL 48 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY ca.hadm_id
),
all_admissions AS (
  SELECT 
    hadm_id, 
    admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
general_lab_flag AS (
  SELECT 
    aa.hadm_id,
    MAX(CASE WHEN le.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS has_critical_lab
  FROM all_admissions aa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON aa.hadm_id = le.hadm_id
    AND le.charttime BETWEEN aa.admittime AND DATETIME_ADD(aa.admittime, INTERVAL 48 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY aa.hadm_id
)

SELECT 
  APPROX_QUANTILES(critical_lab_count, 1000)[OFFSET(250)] AS percentile_25_instability_score,
  (SELECT AVG(hospital_expire_flag) FROM cohort_admissions) AS mortality_rate_cohort,
  (SELECT AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) FROM cohort_admissions) AS mean_los_days_cohort,
  (SELECT AVG(has_critical_lab) FROM cohort_lab_flag) AS cohort_critical_lab_rate,
  (SELECT AVG(has_critical_lab) FROM general_lab_flag) AS general_critical_lab_rate
FROM cohort_lab_scores;
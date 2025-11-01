WITH heart_failure_patients AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND di.long_title LIKE '%heart failure%'
),
creatinine_labs AS (
  SELECT 
    hfp.subject_id, 
    le.valuenum
  FROM heart_failure_patients hfp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON hfp.hadm_id = le.hadm_id
    AND le.itemid = 50912
    AND le.charttime BETWEEN hfp.admittime AND hfp.admittime + INTERVAL '48' HOUR
),
creatinine_sd AS (
  SELECT 
    subject_id, 
    STDDEV(valuenum) AS creatinine_sd
  FROM creatinine_labs
  GROUP BY subject_id
),
threshold AS (
  SELECT 
    APPROX_QUANTILES(cs.creatinine_sd, 100)[OFFSET(95)] AS threshold_value
  FROM creatinine_sd cs
  WHERE cs.creatinine_sd IS NOT NULL
),
critical_lab AS (
  SELECT 
    hfp.subject_id,
    MAX(CASE WHEN le.flag IN ('H', 'L', 'A') THEN 1 ELSE 0 END) AS has_critical_lab
  FROM heart_failure_patients hfp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON hfp.hadm_id = le.hadm_id
    AND le.charttime BETWEEN hfp.admittime AND hfp.admittime + INTERVAL '48' HOUR
  GROUP BY hfp.subject_id
),
high_group AS (
  SELECT 
    hfp.subject_id,
    hfp.hospital_expire_flag,
    DATE_DIFF(hfp.dischtime, hfp.admittime, DAY) AS los_days,
    cl.has_critical_lab
  FROM heart_failure_patients hfp
  JOIN creatinine_sd cs ON hfp.subject_id = cs.subject_id
  JOIN threshold t ON 1=1
  JOIN critical_lab cl ON hfp.subject_id = cl.subject_id
  WHERE cs.creatinine_sd >= t.threshold_value
),
low_group AS (
  SELECT 
    hfp.subject_id,
    cl.has_critical_lab
  FROM heart_failure_patients hfp
  JOIN creatinine_sd cs ON hfp.subject_id = cs.subject_id
  JOIN threshold t ON 1=1
  JOIN critical_lab cl ON hfp.subject_id = cl.subject_id
  WHERE cs.creatinine_sd < t.threshold_value
)
SELECT 
  AVG(hg.hospital_expire_flag) AS mortality_rate,
  AVG(hg.los_days) AS mean_los,
  AVG(hg.has_critical_lab) AS high_group_critical_lab_rate,
  (SELECT AVG(has_critical_lab) FROM low_group) AS control_critical_lab_rate
FROM high_group hg;
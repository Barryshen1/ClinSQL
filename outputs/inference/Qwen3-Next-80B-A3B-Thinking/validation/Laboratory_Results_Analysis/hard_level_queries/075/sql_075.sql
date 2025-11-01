WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 42 AND 52
),
dvt_cohort AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.admittime, 
    c.dischtime, 
    c.hospital_expire_flag
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON c.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.long_title LIKE '%deep vein thrombosis%'
),
creatinine_std AS (
  SELECT 
    c.hadm_id, 
    STDDEV(l.valuenum) AS creatinine_std
  FROM dvt_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON c.hadm_id = l.hadm_id
    AND l.itemid = 50912
    AND l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
),
p95 AS (
  SELECT 
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY creatinine_std) AS p95
  FROM creatinine_std
),
high_instability AS (
  SELECT 
    c.hadm_id, 
    c.hospital_expire_flag, 
    c.dischtime, 
    c.admittime
  FROM dvt_cohort c
  JOIN creatinine_std cs 
    ON c.hadm_id = cs.hadm_id
  JOIN p95 
    ON cs.creatinine_std >= p95.p95
),
mortality_and_los AS (
  SELECT 
    AVG(CAST(hospital_expire_flag AS INT64)) AS mortality_rate,
    AVG(DATE_DIFF(dischtime, admittime, DAY)) AS mean_los
  FROM high_instability
),
critical_lab_high AS (
  SELECT 
    SAFE_DIVIDE(
      COUNTIF(k.valuenum < 3.5 OR k.valuenum > 5.0),
      COUNT(DISTINCT hi.hadm_id)
    ) AS critical_lab_rate_high
  FROM high_instability hi
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` k 
    ON hi.hadm_id = k.hadm_id
    AND k.itemid = 50971
    AND k.charttime BETWEEN hi.admittime AND TIMESTAMP_ADD(hi.admittime, INTERVAL 72 HOUR)
),
critical_lab_all AS (
  SELECT 
    SAFE_DIVIDE(
      COUNTIF(k.valuenum < 3.5 OR k.valuenum > 5.0),
      COUNT(DISTINCT a.hadm_id)
    ) AS critical_lab_rate_all
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` k 
    ON a.hadm_id = k.hadm_id
    AND k.itemid = 50971
    AND k.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
)
SELECT 
  mortality_rate,
  mean_los,
  critical_lab_rate_high,
  critical_lab_rate_all
FROM mortality_and_los, critical_lab_high, critical_lab_all;
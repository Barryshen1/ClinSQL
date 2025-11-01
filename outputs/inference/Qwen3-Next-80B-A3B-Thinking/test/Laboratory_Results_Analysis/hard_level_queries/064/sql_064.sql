WITH cohort AS (
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
  WHERE 
    d.icd_code LIKE 'K85%' 
    AND d.icd_version = 10
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
),

lab_counts AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    COUNT(l.labevent_id) AS critical_lab_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND c.admittime + INTERVAL '48' HOUR
    AND l.flag IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id
),

cohort_with_los AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.hospital_expire_flag,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los,
    COALESCE(lc.critical_lab_count, 0) AS critical_lab_count
  FROM cohort c
  LEFT JOIN lab_counts lc 
    ON c.subject_id = lc.subject_id AND c.hadm_id = lc.hadm_id
),

quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY critical_lab_count) AS quintile
  FROM cohort_with_los
)

SELECT 
  quintile,
  COUNT(*) AS count,
  AVG(critical_lab_count) AS mean_instability,
  AVG(los) AS mean_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate,
  AVG(CASE WHEN critical_lab_count > 0 THEN 1 ELSE 0 END) * 100 AS percent_with_critical_labs
FROM quintiles
GROUP BY quintile
ORDER BY quintile;
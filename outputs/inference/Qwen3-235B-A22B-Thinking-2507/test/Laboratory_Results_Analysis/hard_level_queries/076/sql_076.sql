WITH admissions_with_age AS (
  SELECT 
    a.*,
    p.gender,  -- Added to include gender from patients table
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
)
, cohort AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag
  FROM admissions_with_age
  WHERE gender = 'M'
    AND age_at_admission BETWEEN 87 AND 97
)
, lab_instability AS (
  SELECT
    c.hadm_id,
    SUM(CASE WHEN 
             (l.ref_range_lower IS NOT NULL AND l.ref_range_upper IS NOT NULL AND 
               (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
             )
             OR 
             (l.flag IN ('abnormal', 'high', 'low'))
           THEN 1 ELSE 0 END) AS critical_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime >= c.admittime
    AND l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
  GROUP BY c.hadm_id
)
, p95_value AS (
  SELECT 
    APPROX_QUANTILES(critical_count, 1000)[OFFSET(950)] AS p95
  FROM lab_instability
)
, high_risk AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    li.critical_count
  FROM cohort c
  INNER JOIN lab_instability li
    ON c.hadm_id = li.hadm_id
  WHERE li.critical_count >= (SELECT p95 FROM p95_value)
)
, high_risk_metrics AS (
  SELECT 
    AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(critical_count) AS high_risk_avg_critical
  FROM high_risk
)
, general_lab AS (
  SELECT
    a.hadm_id,
    SUM(CASE WHEN 
             (l.ref_range_lower IS NOT NULL AND l.ref_range_upper IS NOT NULL AND 
               (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
             )
             OR 
             (l.flag IN ('abnormal', 'high', 'low'))
           THEN 1 ELSE 0 END) AS critical_count_general
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
    AND l.charttime >= a.admittime
    AND l.charttime <= DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
  GROUP BY a.hadm_id
)
, general_avg AS (
  SELECT AVG(critical_count_general) AS general_avg_critical
  FROM general_lab
)
SELECT 
  hrm.mean_los,
  hrm.mortality_rate,
  hrm.high_risk_avg_critical,
  ga.general_avg_critical
FROM high_risk_metrics hrm
CROSS JOIN general_avg ga;
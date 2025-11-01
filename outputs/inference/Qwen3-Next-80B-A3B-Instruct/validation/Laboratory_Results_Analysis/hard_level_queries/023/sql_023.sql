WITH target_cohort AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
    AND LOWER(di.long_title) LIKE '%acute myocardial infarction%'
),

lab_instability AS (
  SELECT 
    t.hadm_id,
    COUNT(*) AS lab_instability_score
  FROM target_cohort t
  JOIN physionet-data.mimiciv_3_1_hosp.labevents le ON t.hadm_id = le.hadm_id
  WHERE le.charttime >= t.admittime
    AND le.charttime <= t.admittime + INTERVAL '48' HOUR
    AND le.flag IN ('H', 'L')
  GROUP BY t.hadm_id
),

p75_threshold AS (
  SELECT PERCENTILE_CONT(lab_instability_score, 0.75) AS p75_score
  FROM lab_instability
),

high_instability AS (
  SELECT li.hadm_id
  FROM lab_instability li
  CROSS JOIN p75_threshold p
  WHERE li.lab_instability_score >= p.p75_score
),

all_90_100 AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
),

all_lab_instability AS (
  SELECT 
    a.hadm_id,
    COUNT(*) AS lab_instability_score
  FROM all_90_100 a
  JOIN physionet-data.mimiciv_3_1_hosp.labevents le ON a.hadm_id = le.hadm_id
  WHERE le.charttime >= a.admittime
    AND le.charttime <= a.admittime + INTERVAL '48' HOUR
    AND le.flag IN ('H', 'L')
  GROUP BY a.hadm_id
),

critical_lab_rates AS (
  SELECT 
    'High Instability (≥P75, AMI)' AS group_label,
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS mean_los_days,
    COUNT(DISTINCT CASE WHEN cl.flag IS NOT NULL THEN a.hadm_id END) * 1.0 / COUNT(DISTINCT a.hadm_id) AS critical_lab_rate
  FROM high_instability hi
  JOIN target_cohort a ON hi.hadm_id = a.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.labevents cl ON a.hadm_id = cl.hadm_id
    AND cl.charttime >= a.admittime
    AND cl.charttime <= a.admittime + INTERVAL '48' HOUR
    AND cl.flag IN ('H', 'L')
  GROUP BY group_label

  UNION ALL

  SELECT 
    'All Female 90–100' AS group_label,
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS mean_los_days,
    COUNT(DISTINCT CASE WHEN cl.flag IS NOT NULL THEN a.hadm_id END) * 1.0 / COUNT(DISTINCT a.hadm_id) AS critical_lab_rate
  FROM all_90_100 a
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.labevents cl ON a.hadm_id = cl.hadm_id
    AND cl.charttime >= a.admittime
    AND cl.charttime <= a.admittime + INTERVAL '48' HOUR
    AND cl.flag IN ('H', 'L')
  GROUP BY group_label
)

SELECT group_label, in_hospital_mortality, mean_los_days, critical_lab_rate
FROM critical_lab_rates;
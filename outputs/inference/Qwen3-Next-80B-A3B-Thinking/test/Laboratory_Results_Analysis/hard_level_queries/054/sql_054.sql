WITH amipatients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE a.hadm_id IN (
    SELECT hadm_id 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'
  )
  AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 38 AND 48
),

labevents_72h AS (
  SELECT 
    l.subject_id, 
    l.hadm_id, 
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN amipatients a 
    ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE l.itemid = 50911
    AND l.charttime BETWEEN a.admittime AND a.admittime + INTERVAL '72' HOUR
),

troponin_sd AS (
  SELECT 
    subject_id, 
    hadm_id, 
    STDDEV(valuenum) AS troponin_sd
  FROM labevents_72h
  GROUP BY subject_id, hadm_id
),

quartiles AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    COALESCE(t.troponin_sd, 0) AS score,
    NTILE(4) OVER (ORDER BY COALESCE(t.troponin_sd, 0)) AS quartile
  FROM amipatients a
  LEFT JOIN troponin_sd t 
    ON a.subject_id = t.subject_id AND a.hadm_id = t.hadm_id
),

quartile_results AS (
  SELECT 
    quartile,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM quartiles
  GROUP BY quartile
),

control_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 38 AND 48
    AND a.hadm_id NOT IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'
    )
),

critical_lab_ami AS (
  SELECT 
    a.subject_id, 
    a.hadm_id,
    MAX(CASE WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1 ELSE 0 END) AS has_critical_lab
  FROM amipatients a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
  WHERE l.charttime BETWEEN a.admittime AND a.admittime + INTERVAL '72' HOUR
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
  GROUP BY a.subject_id, a.hadm_id
),

critical_lab_control AS (
  SELECT 
    c.subject_id, 
    c.hadm_id,
    MAX(CASE WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1 ELSE 0 END) AS has_critical_lab
  FROM control_patients c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  WHERE l.charttime BETWEEN c.admittime AND c.admittime + INTERVAL '72' HOUR
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id
),

critical_lab_rates AS (
  SELECT 'AMI' AS group_name, AVG(has_critical_lab) AS rate
  FROM critical_lab_ami
  UNION ALL
  SELECT 'Control', AVG(has_critical_lab)
  FROM critical_lab_control
)

SELECT 
  'Quartile' AS category,
  CAST(quartile AS STRING) AS quartile,
  CAST(avg_los AS STRING) AS avg_los,
  CAST(mortality_rate AS STRING) AS mortality_rate
FROM quartile_results
UNION ALL
SELECT 
  'Critical Lab Rate' AS category,
  group_name,
  CAST(rate AS STRING),
  NULL
FROM critical_lab_rates;
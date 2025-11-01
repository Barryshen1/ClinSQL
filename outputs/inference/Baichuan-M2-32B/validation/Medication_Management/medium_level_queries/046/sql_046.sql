WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    TIMESTAMP_DIFF(
      a.admittime, 
      TIMESTAMP(DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR)), 
      YEAR
    ) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    a.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(
      a.admittime, 
      TIMESTAMP(DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR)), 
      YEAR
    ) BETWEEN 63 AND 73
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'E11%'
        AND d.icd_version = 10
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'I50%'
        AND d.icd_version = 10
    )
),
time_periods AS (
  SELECT 
    subject_id, 
    hadm_id, 
    admittime, 
    dischtime,
    admittime AS first_24h_start,
    admittime + INTERVAL 24 HOUR AS first_24h_end,
    dischtime - INTERVAL 24 HOUR AS final_24h_start,
    dischtime AS final_24h_end
  FROM cohort
),
prescriptions_with_flags AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug,
    CASE WHEN LOWER(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 END AS is_insulin,
    CASE 
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%glipizide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%glyburide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%glimepiride%' THEN 1
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' THEN 1
      WHEN LOWER(p.drug) LIKE '%rosiglitazone%' THEN 1
      WHEN LOWER(p.drug) LIKE '%saxagliptin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%linagliptin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%alogliptin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%dapagliflozin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%canagliflozin%' THEN 1
      ELSE 0 
    END AS is_oral_agent
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN time_periods t 
    ON p.hadm_id = t.hadm_id
  WHERE 
    (p.starttime <= t.first_24h_end AND (p.stoptime >= t.first_24h_start OR p.stoptime IS NULL))
    OR
    (p.starttime <= t.final_24h_end AND (p.stoptime >= t.final_24h_start OR p.stoptime IS NULL))
),
admission_med_flags AS (
  SELECT 
    t.subject_id,
    t.hadm_id,
    MAX(CASE WHEN p.is_insulin = 1 AND 
             (p.starttime <= t.first_24h_end AND (p.stoptime >= t.first_24h_start OR p.stoptime IS NULL)) 
             THEN 1 ELSE 0 END) AS has_insulin_first,
    MAX(CASE WHEN p.is_oral_agent = 1 AND 
             (p.starttime <= t.first_24h_end AND (p.stoptime >= t.first_24h_start OR p.stoptime IS NULL)) 
             THEN 1 ELSE 0 END) AS has_oral_agent_first,
    MAX(CASE WHEN p.is_insulin = 1 AND 
             (p.starttime <= t.final_24h_end AND (p.stoptime >= t.final_24h_start OR p.stoptime IS NULL)) 
             THEN 1 ELSE 0 END) AS has_insulin_final,
    MAX(CASE WHEN p.is_oral_agent = 1 AND 
             (p.starttime <= t.final_24h_end AND (p.stoptime >= t.final_24h_start OR p.stoptime IS NULL)) 
             THEN 1 ELSE 0 END) AS has_oral_agent_final
  FROM time_periods t
  LEFT JOIN prescriptions_with_flags p 
    ON t.hadm_id = p.hadm_id
  GROUP BY t.subject_id, t.hadm_id
),
aggregated AS (
  SELECT 
    'insulin' AS medication_type,
    'first_24h' AS period,
    COUNT(CASE WHEN has_insulin_first = 1 THEN 1 END) * 100.0 / COUNT(*) AS prevalence
  FROM admission_med_flags
  UNION ALL
  SELECT 
    'insulin' AS medication_type,
    'final_24h' AS period,
    COUNT(CASE WHEN has_insulin_final = 1 THEN 1 END) * 100.0 / COUNT(*) AS prevalence
  FROM admission_med_flags
  UNION ALL
  SELECT 
    'oral_agent' AS medication_type,
    'first_24h' AS period,
    COUNT(CASE WHEN has_oral_agent_first = 1 THEN 1 END) * 100.0 / COUNT(*) AS prevalence
  FROM admission_med_flags
  UNION ALL
  SELECT 
    'oral_agent' AS medication_type,
    'final_24h' AS period,
    COUNT(CASE WHEN has_oral_agent_final = 1 THEN 1 END) * 100.0 / COUNT(*) AS prevalence
  FROM admission_med_flags
),
net_change AS (
  SELECT 
    medication_type,
    MAX(CASE WHEN period = 'final_24h' THEN prevalence END) - 
    MAX(CASE WHEN period = 'first_24h' THEN prevalence END) AS net_change
  FROM aggregated
  GROUP BY medication_type
)
SELECT 
  a.medication_type,
  a.period,
  a.prevalence,
  n.net_change
FROM aggregated a
LEFT JOIN net_change n 
  ON a.medication_type = n.medication_type
ORDER BY a.medication_type, a.period;
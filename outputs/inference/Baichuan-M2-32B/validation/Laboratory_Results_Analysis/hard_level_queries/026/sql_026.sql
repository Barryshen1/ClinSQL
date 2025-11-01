WITH hepatic_icd_codes AS (
  SELECT 'K70.9' AS icd_code
  UNION ALL SELECT 'K72.9'
  UNION ALL SELECT 'K72.1'
),
hepatic_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN hepatic_icd_codes h
    ON d.icd_code = h.icd_code
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND d.icd_version = 10
),
bilirubin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%bilirubin%' AND label LIKE '%total%'
),
hepatic_bilirubin AS (
  SELECT 
    h.hadm_id, 
    MAX(l.valuenum) AS max_bilirubin
  FROM hepatic_patients h
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON h.subject_id = l.subject_id AND h.hadm_id = l.hadm_id
  JOIN bilirubin_items b
    ON l.itemid = b.itemid
  WHERE l.charttime BETWEEN h.admittime 
    AND TIMESTAMP_ADD(h.admittime, INTERVAL 48 HOUR)
  GROUP BY h.hadm_id
),
hepatic_critical_labs AS (
  SELECT 
    h.hadm_id, 
    COUNT(*) AS critical_lab_count
  FROM hepatic_patients h
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON h.subject_id = l.subject_id AND h.hadm_id = l.hadm_id
  WHERE l.flag IN ('H', 'L', 'HH', 'LL')
    AND l.charttime BETWEEN h.admittime 
      AND TIMESTAMP_ADD(h.admittime, INTERVAL 48 HOUR)
  GROUP BY h.hadm_id
),
general_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.hadm_id NOT IN (SELECT hadm_id FROM hepatic_patients)
),
general_critical_labs AS (
  SELECT 
    g.hadm_id, 
    COUNT(*) AS critical_lab_count
  FROM general_patients g
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON g.subject_id = l.subject_id AND g.hadm_id = l.hadm_id
  WHERE l.flag IN ('H', 'L', 'HH', 'LL')
    AND l.charttime BETWEEN g.admittime 
      AND TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
  GROUP BY g.hadm_id
),
hepatic_agg AS (
  SELECT 
    MAX(b.max_bilirubin) AS cohort_max_instability_score,
    AVG(hp.hospital_expire_flag) AS mortality_rate,
    AVG(hp.los) AS avg_los,
    (SELECT AVG(critical_lab_count) FROM hepatic_critical_labs) AS avg_critical_labs_hepatic
  FROM hepatic_patients hp
  LEFT JOIN hepatic_bilirubin b ON hp.hadm_id = b.hadm_id
),
general_agg AS (
  SELECT 
    (SELECT AVG(critical_lab_count) FROM general_critical_labs) AS avg_critical_labs_general
)
SELECT 
  h.cohort_max_instability_score,
  h.mortality_rate,
  h.avg_los,
  h.avg_critical_labs_hepatic,
  g.avg_critical_labs_general
FROM hepatic_agg h, general_agg g;
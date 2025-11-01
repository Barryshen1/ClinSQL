WITH
-- Define septic shock ICD codes (example codes - adjust as needed)
septic_shock_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%septic shock%'
    OR LOWER(long_title) LIKE '%sepsis with shock%'
),

-- Get all male patients 63-73 with septic shock and >15 diagnoses
target_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    p.dod,
    a.hospital_expire_flag,
    COUNT(DISTINCT d.seq_num) AS diagnosis_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN septic_shock_codes s ON d.icd_code = s.icd_code
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
  GROUP BY p.subject_id, a.hadm_id, p.anchor_age, a.admittime, p.dod, a.hospital_expire_flag
  HAVING COUNT(DISTINCT d.seq_num) > 15
),

-- Get SAPS-II scores (example itemid - verify in your data)
risk_scores AS (
  SELECT
    subject_id,
    hadm_id,
    AVG(valuenum) AS mean_saps_score
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE itemid = 223900  -- SAPS-II score itemid
  GROUP BY subject_id, hadm_id
),

-- Calculate 90-day mortality
mortality AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    CASE
      WHEN t.dod IS NOT NULL AND DATE_DIFF(DATE(t.dod), DATE(t.admittime), DAY) <= 90 THEN 1
      WHEN t.hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS died_within_90_days
  FROM target_patients t
),

-- General inpatient comparison group (male 63-73 without septic shock)
general_inpatients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    p.dod,
    a.hospital_expire_flag,
    COUNT(DISTINCT d.seq_num) AS diagnosis_count,
    CASE
      WHEN p.dod IS NOT NULL AND DATE_DIFF(DATE(p.dod), DATE(a.admittime), DAY) <= 90 THEN 1
      WHEN a.hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS died_within_90_days,
    -- Calculate LOS (in days)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Major complications (example - adjust as needed)
    MAX(CASE WHEN d.icd_code IN (
      SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
      WHERE LOWER(long_title) LIKE '%complication%'
    ) THEN 1 ELSE 0 END) AS has_major_complication
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.hadm_id NOT IN (SELECT hadm_id FROM target_patients)
  GROUP BY p.subject_id, a.hadm_id, p.anchor_age, a.admittime, p.dod, a.hospital_expire_flag, a.dischtime
),

-- Calculate percentiles for the specific profile (68M, 16 diagnoses)
percentile_calc AS (
  SELECT
    PERCENT_RANK() OVER (ORDER BY diagnosis_count) AS percentile
  FROM general_inpatients
  WHERE anchor_age = 68 AND diagnosis_count = 16
  LIMIT 1
)

-- Final results
SELECT
  -- For target patients (septic shock)
  'Septic Shock Patients' AS group_name,
  AVG(r.mean_saps_score) AS mean_risk_score,
  AVG(m.died_within_90_days) AS mortality_rate_90_day,
  AVG(CASE WHEN m.died_within_90_days = 0 THEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) END) AS avg_los_survivors,
  AVG(CASE WHEN d.icd_code IN (
    SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE LOWER(long_title) LIKE '%complication%'
  ) THEN 1 ELSE 0 END) AS major_complication_rate,

  -- For general inpatients
  'General Inpatients' AS comparison_group,
  AVG(CASE WHEN g.died_within_90_days = 0 THEN g.los_days END) AS comparison_avg_los,
  AVG(g.has_major_complication) AS comparison_complication_rate,

  -- Percentile for specific profile
  (SELECT percentile FROM percentile_calc) AS percentile_for_68m_16_diagnoses
FROM target_patients t
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON t.subject_id = a.subject_id AND t.hadm_id = a.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON t.subject_id = d.subject_id AND t.hadm_id = d.hadm_id
LEFT JOIN risk_scores r ON t.subject_id = r.subject_id AND t.hadm_id = r.hadm_id
LEFT JOIN mortality m ON t.subject_id = m.subject_id AND t.hadm_id = m.hadm_id
CROSS JOIN general_inpatients g
GROUP BY group_name, comparison_group;
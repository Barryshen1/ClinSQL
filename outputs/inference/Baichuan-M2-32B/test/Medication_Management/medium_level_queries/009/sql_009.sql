WITH
  eligible_patients AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 68 AND 78
      AND a.dischtime - a.admittime >= INTERVAL 24 HOUR  -- Ensure admission duration >= 24h
  ),
  diabetes_admissions AS (
    SELECT
      e.subject_id,
      e.hadm_id,
      e.admittime,  -- Added to propagate
      e.dischtime   -- Added to propagate
    FROM
      eligible_patients e
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON e.subject_id = d.subject_id AND e.hadm_id = d.hadm_id
    WHERE
      d.icd_version = 10
      AND REGEXP_CONTAINS(d.icd_code, r'^E1[0-4]')  -- ICD-10 codes for diabetes (E10-E14)
  ),
  hf_admissions AS (
    SELECT
      e.subject_id,
      e.hadm_id,
      e.admittime,  -- Added to propagate
      e.dischtime   -- Added to propagate
    FROM
      eligible_patients e
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON e.subject_id = d.subject_id AND e.hadm_id = d.hadm_id
    WHERE
      d.icd_version = 10
      AND d.icd_code IN ('I50.1', 'I50.2', 'I50.9')  -- Common ICD-10 codes for acute HF
  ),
  cohort_admissions AS (
    SELECT
      d.subject_id,
      d.hadm_id,
      d.admittime,  -- Now available from diabetes_admissions
      d.dischtime   -- Now available from diabetes_admissions
    FROM
      diabetes_admissions d
    INNER JOIN
      hf_admissions h
      ON d.subject_id = h.subject_id AND d.hadm_id = h.hadm_id
  ),
  insulin_orders AS (
    SELECT
      p.hadm_id,
      MIN(p.starttime) AS first_insulin_time
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE
      p.drug LIKE '%insulin%'  -- Insulin initiation
    GROUP BY
      p.hadm_id
  ),
  oral_agent_orders AS (
    SELECT
      p.hadm_id,
      MIN(p.starttime) AS first_oral_agent_time
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE
      -- List of common oral diabetes agents (adjust as needed)
      p.drug LIKE '%metformin%' OR
      p.drug LIKE '%glipizide%' OR
      p.drug LIKE '%glyburide%' OR
      p.drug LIKE '%glimepiride%' OR
      p.drug LIKE '%rosiglitazone%' OR
      p.drug LIKE '%pioglitazone%' OR
      p.drug LIKE '%sitagliptin%' OR
      p.drug LIKE '%saxagliptin%' OR
      p.drug LIKE '%linagliptin%' OR
      p.drug LIKE '%alogliptin%' OR
      p.drug LIKE '%canagliflozin%' OR
      p.drug LIKE '%dapagliflozin%' OR
      p.drug LIKE '%empagliflozin%' OR
      p.drug LIKE '%semaglutide%' OR
      p.drug LIKE '%liraglutide%'
    GROUP BY
      p.hadm_id
  ),
  admission_data AS (
    SELECT
      c.subject_id,
      c.hadm_id,
      c.admittime,
      c.dischtime,
      i.first_insulin_time,
      o.first_oral_agent_time
    FROM
      cohort_admissions c
    LEFT JOIN
      insulin_orders i
      ON c.hadm_id = i.hadm_id
    LEFT JOIN
      oral_agent_orders o
      ON c.hadm_id = o.hadm_id
  ),
  period_flags AS (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      first_insulin_time,
      first_oral_agent_time,
      -- First 24h period flags
      CASE WHEN first_insulin_time BETWEEN admittime AND admittime + INTERVAL 24 HOUR THEN 1 ELSE 0 END AS insulin_first_24h,
      CASE WHEN first_oral_agent_time BETWEEN admittime AND admittime + INTERVAL 24 HOUR THEN 1 ELSE 0 END AS oral_agent_first_24h,
      -- Final 24h period flags
      CASE WHEN first_insulin_time BETWEEN dischtime - INTERVAL 24 HOUR AND dischtime THEN 1 ELSE 0 END AS insulin_final_24h,
      CASE WHEN first_oral_agent_time BETWEEN dischtime - INTERVAL 24 HOUR AND dischtime THEN 1 ELSE 0 END AS oral_agent_final_24h
    FROM
      admission_data
  )
-- Calculate rates and differences
SELECT
  COUNT(*) AS total_patients,
  SUM(insulin_first_24h) AS insulin_first_24h_count,
  SUM(insulin_first_24h) * 100.0 / COUNT(*) AS insulin_first_24h_rate,
  SUM(insulin_final_24h) AS insulin_final_24h_count,
  SUM(insulin_final_24h) * 100.0 / COUNT(*) AS insulin_final_24h_rate,
  (SUM(insulin_final_24h) * 100.0 / COUNT(*) - SUM(insulin_first_24h) * 100.0 / COUNT(*)) AS diff_insulin,
  SUM(oral_agent_first_24h) AS oral_agent_first_24h_count,
  SUM(oral_agent_first_24h) * 100.0 / COUNT(*) AS oral_agent_first_24h_rate,
  SUM(oral_agent_final_24h) AS oral_agent_final_24h_count,
  SUM(oral_agent_final_24h) * 100.0 / COUNT(*) AS oral_agent_final_24h_rate,
  (SUM(oral_agent_final_24h) * 100.0 / COUNT(*) - SUM(oral_agent_first_24h) * 100.0 / COUNT(*)) AS diff_oral_agent
FROM
  period_flags;
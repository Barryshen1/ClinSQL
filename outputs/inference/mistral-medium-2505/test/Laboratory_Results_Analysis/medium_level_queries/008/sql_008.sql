WITH
-- Define ACS ICD codes
acs_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN (
    '410', '410.0', '410.1', '410.2', '410.3', '410.4', '410.5', '410.6', '410.7', '410.8', '410.9',
    '411', '411.0', '411.1', '411.8', '411.81', '411.89',
    '413', '413.0', '413.1', '413.9',
    'I20', 'I20.0', 'I20.1', 'I20.8', 'I20.9',
    'I21', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9',
    'I22', 'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9',
    'I24', 'I24.0', 'I24.1', 'I24.8', 'I24.9'
  )
),

-- Get Troponin T itemids
troponin_t_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

-- Get first admission with ACS diagnosis for each patient
first_acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN acs_icd_codes acs ON d.icd_code = acs.icd_code
  WHERE a.subject_id IN (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 87 AND 97
  )
),

-- Get first Troponin T measurement for each admission
first_troponin_t AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS troponin_rank
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_t_itemids t ON l.itemid = t.itemid
  WHERE l.hadm_id IN (SELECT hadm_id FROM first_acs_admissions WHERE admission_rank = 1)
),

-- Categorize Troponin T levels
troponin_categories AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.hospital_expire_flag,
    CASE
      WHEN t.valuenum < 0.01 THEN 'Normal/Minimal'
      WHEN t.valuenum BETWEEN 0.01 AND 0.03 THEN 'Borderline'
      WHEN t.valuenum > 0.03 THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category
  FROM first_acs_admissions f
  JOIN first_troponin_t t ON f.hadm_id = t.hadm_id AND t.troponin_rank = 1
  WHERE f.admission_rank = 1
)

-- Final aggregation
SELECT
  troponin_category,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS mortality_rate
FROM troponin_categories
GROUP BY troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal/Minimal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 4
  END;
WITH
-- Get female patients aged 67-77
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 67 AND 77
),

-- Get admissions with ACS diagnosis (I20-I25 range)
acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    female_patients fp
  ON
    a.subject_id = fp.subject_id
  WHERE
    d.icd_code BETWEEN 'I20' AND 'I25'
    AND d.icd_version = 10
),

-- Get first Troponin T measurement per admission
first_troponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.itemid,
    le.valuenum,
    le.charttime,
    aa.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
  ON
    le.itemid = dli.itemid
  JOIN
    acs_admissions aa
  ON
    le.subject_id = aa.subject_id AND le.hadm_id = aa.hadm_id
  WHERE
    dli.label LIKE '%Troponin T%'
    AND le.valuenum IS NOT NULL
),

-- Categorize Troponin T values
troponin_categories AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN valuenum <= 0.04 THEN 'Normal (≤0.04)'
      WHEN valuenum > 0.04 AND valuenum <= 0.1 THEN 'Borderline (>0.04–0.1)'
      WHEN valuenum > 0.1 THEN 'Elevated (>0.1)'
    END AS troponin_category,
    hospital_expire_flag
  FROM
    first_troponin
  WHERE
    rn = 1  -- Only first measurement per admission
)

-- Final aggregation
SELECT
  troponin_category,
  COUNT(*) AS admission_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percent_of_admissions,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS mortality_rate
FROM
  troponin_categories
GROUP BY
  troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal (≤0.04)' THEN 1
    WHEN 'Borderline (>0.04–0.1)' THEN 2
    WHEN 'Elevated (>0.1)' THEN 3
  END;
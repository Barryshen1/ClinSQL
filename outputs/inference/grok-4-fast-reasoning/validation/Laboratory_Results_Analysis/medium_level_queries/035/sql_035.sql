WITH patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 73 AND 83
),
acs_adms AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN patients p ON d.subject_id = p.subject_id
  WHERE seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code = 'I20.0'))
    )
),
first_trop AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN patients p ON le.subject_id = p.subject_id
  WHERE le.itemid = 50586  -- Troponin T
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) = 1
),
elevated AS (
  SELECT
    subject_id,
    hadm_id
  FROM first_trop
  WHERE valuenum > 0.01  -- Elevated threshold
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN elevated e ON a.hadm_id = e.hadm_id
  JOIN acs_adms aa ON a.hadm_id = aa.hadm_id
)
SELECT
  COUNT(*) AS num_qualifying_admissions,
  COUNT(DISTINCT subject_id) AS num_unique_patients,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS in_hospital_mortality_rate
FROM cohort;
WITH
-- Get male patients aged 89-99
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 89 AND 99
),

-- Get admissions with hemorrhagic stroke (ICD-10 I61.*)
stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COUNT(DISTINCT d.icd_code) AS stroke_diagnoses
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    eligible_patients p ON a.subject_id = p.subject_id
  WHERE
    d.icd_code LIKE 'I61.%'
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  HAVING
    COUNT(DISTINCT d.icd_code) > 0
),

-- Get medication complexity (unique drugs in first 7 days)
medication_complexity AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_drugs
  FROM
    stroke_admissions s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON s.subject_id = p.subject_id AND s.hadm_id = p.hadm_id
  WHERE
    p.starttime BETWEEN s.admittime AND DATETIME_ADD(s.admittime, INTERVAL 7 DAY)
  GROUP BY
    s.subject_id, s.hadm_id
),

-- Create quintiles based on medication complexity
quintiles AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.unique_drugs,
    NTILE(5) OVER (ORDER BY m.unique_drugs) AS complexity_quintile
  FROM
    medication_complexity m
),

-- Calculate outcomes
outcomes AS (
  SELECT
    q.complexity_quintile,
    COUNT(DISTINCT q.subject_id) AS patient_count,
    AVG(DATETIME_DIFF(s.dischtime, s.admittime, DAY)) AS avg_los,
    SUM(CASE WHEN s.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS inpatient_deaths,
    -- 30-day readmission calculation
    COUNT(DISTINCT CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = q.subject_id
        AND a2.admittime > s.dischtime
        AND a2.admittime <= DATETIME_ADD(s.dischtime, INTERVAL 30 DAY)
        AND a2.hadm_id != q.hadm_id
      ) THEN q.subject_id
    END) AS readmissions_30d
  FROM
    quintiles q
  JOIN
    stroke_admissions s ON q.subject_id = s.subject_id AND q.hadm_id = s.hadm_id
  GROUP BY
    q.complexity_quintile
)

-- Final results
SELECT
  complexity_quintile,
  patient_count,
  avg_los,
  inpatient_deaths,
  readmissions_30d,
  ROUND(inpatient_deaths * 100.0 / patient_count, 2) AS mortality_rate,
  ROUND(readmissions_30d * 100.0 / patient_count, 2) AS readmission_rate
FROM
  outcomes
ORDER BY
  complexity_quintile;
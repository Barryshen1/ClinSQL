WITH
-- Get male patients aged 82-92
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 82 AND 92
),

-- Get patients with cardiogenic shock (ICD-9: 785.51, ICD-10: R57.0)
cardiogenic_shock_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    (d.icd_code = '78551' AND d.icd_version = '9')
    OR (d.icd_code = 'R570' AND d.icd_version = '10')
),

-- Get first ICU stay for each patient
first_icu_stays AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime AS icu_intime,
    outtime AS icu_outtime
  FROM (
    SELECT
      s.subject_id,
      s.hadm_id,
      s.stay_id,
      s.intime,
      s.outtime,
      ROW_NUMBER() OVER (PARTITION BY s.subject_id ORDER BY s.intime) AS stay_rank
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` s
    JOIN
      cardiogenic_shock_patients c
    ON
      s.subject_id = c.subject_id
      AND s.hadm_id = c.hadm_id
  )
  WHERE
    stay_rank = 1
),

-- Count ICU procedures in first 24 hours
icu_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    COUNT(DISTINCT p.itemid) AS icu_procedure_count
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN
    first_icu_stays s
  ON
    p.subject_id = s.subject_id
    AND p.hadm_id = s.hadm_id
    AND p.stay_id = s.stay_id
  WHERE
    p.charttime BETWEEN s.icu_intime AND TIMESTAMP_ADD(s.icu_intime, INTERVAL 24 HOUR)
  GROUP BY
    p.subject_id, p.hadm_id, p.stay_id
),

-- Count hospital procedures in first 24 hours of ICU stay
hospital_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.icd_code) AS hospital_procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    first_icu_stays s
  ON
    p.subject_id = s.subject_id
    AND p.hadm_id = s.hadm_id
  WHERE
    p.chartdate BETWEEN CAST(s.icu_intime AS DATE) AND DATE(TIMESTAMP_ADD(s.icu_intime, INTERVAL 24 HOUR))
  GROUP BY
    p.subject_id, p.hadm_id
),

-- Combine procedure counts
combined_procedures AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    COALESCE(i.icu_procedure_count, 0) AS icu_procedure_count,
    COALESCE(h.hospital_procedure_count, 0) AS hospital_procedure_count,
    COALESCE(i.icu_procedure_count, 0) + COALESCE(h.hospital_procedure_count, 0) AS total_procedure_count
  FROM
    first_icu_stays s
  LEFT JOIN
    icu_procedures i
  ON
    s.subject_id = i.subject_id
    AND s.hadm_id = i.hadm_id
    AND s.stay_id = i.stay_id
  LEFT JOIN
    hospital_procedures h
  ON
    s.subject_id = h.subject_id
    AND s.hadm_id = h.hadm_id
),

-- Add hospital outcomes
patient_outcomes AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.total_procedure_count,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los_days,
    NTILE(5) OVER (ORDER BY c.total_procedure_count) AS procedure_quintile
  FROM
    combined_procedures c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    c.subject_id = a.subject_id
    AND c.hadm_id = a.hadm_id
  JOIN
    eligible_patients e
  ON
    c.subject_id = e.subject_id
)

-- Final aggregation by quintile
SELECT
  procedure_quintile,
  COUNT(*) AS patient_count,
  AVG(total_procedure_count) AS mean_procedure_count,
  AVG(hospital_los_days) AS mean_hospital_los_days,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS in_hospital_mortality_percentage
FROM
  patient_outcomes
GROUP BY
  procedure_quintile
ORDER BY
  procedure_quintile;
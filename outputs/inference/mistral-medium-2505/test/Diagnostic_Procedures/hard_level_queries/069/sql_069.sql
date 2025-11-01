WITH
-- Get male patients aged 44-54
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 44 AND 54
),

-- Get patients with pulmonary embolism diagnosis
pe_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    male_patients p ON d.subject_id = p.subject_id
  WHERE
    -- ICD-9 code for pulmonary embolism (415.1) or ICD-10 (I26)
    (d.icd_code LIKE '415.1%' OR d.icd_code LIKE 'I26%')
),

-- Get first ICU stay per admission
first_icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime,
    ROW_NUMBER() OVER (PARTITION BY s.subject_id, s.hadm_id ORDER BY s.intime) AS stay_rank
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    pe_patients p ON s.subject_id = p.subject_id AND s.hadm_id = p.hadm_id
  WHERE
    s.intime IS NOT NULL
),

-- Get procedures in first 72 hours of first ICU stay
early_procedures AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM
    first_icu_stays f
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON f.subject_id = p.subject_id
    AND f.stay_id = p.stay_id
    AND p.starttime BETWEEN f.icu_intime
    AND TIMESTAMP_ADD(f.icu_intime, INTERVAL 72 HOUR)
  WHERE
    f.stay_rank = 1  -- Only first ICU stay
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id
),

-- Calculate quintiles
quintiles AS (
  SELECT
    procedure_count,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM
    early_procedures
),

-- Get hospital LOS and mortality
patient_outcomes AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.procedure_count,
    q.quintile,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los,
    a.hospital_expire_flag
  FROM
    early_procedures e
  JOIN
    quintiles q ON e.procedure_count = q.procedure_count
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON e.subject_id = a.subject_id AND e.hadm_id = a.hadm_id
)

-- Final aggregation by quintile
SELECT
  quintile,
  AVG(procedure_count) AS avg_procedure_count,
  AVG(hospital_los) AS avg_hospital_los_days,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percentage
FROM
  patient_outcomes
GROUP BY
  quintile
ORDER BY
  quintile;
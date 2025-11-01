WITH
-- Define age range and gender
patient_base AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS hospital_los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
),

-- Identify first ICU stay for each patient
first_icu_stay AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    ROW_NUMBER() OVER (PARTITION BY s.subject_id ORDER BY s.intime) AS icu_stay_rank
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    patient_base p
  ON
    s.subject_id = p.subject_id
    AND s.hadm_id = p.hadm_id
),

-- Identify sepsis patients (using ICD-10 codes for sepsis)
sepsis_patients AS (
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
    -- Common sepsis ICD-10 codes (simplified example)
    d.icd_code IN (
      'A419', 'A403', 'A410', 'A411', 'A412', 'A413', 'A414', 'A415',
      'A418', 'A419', 'R6520', 'R6521', 'R6510', 'R6511'
    )
),

-- Count distinct procedures in first 48 hours of ICU stay
procedure_counts AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
  FROM
    first_icu_stay f
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  ON
    f.stay_id = pe.stay_id
    AND pe.starttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 48 HOUR)
  WHERE
    f.icu_stay_rank = 1  -- Only first ICU stay
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id
),

-- Calculate 90th percentile of distinct procedures
percentile_90 AS (
  SELECT
    PERCENTILE_CONT(distinct_procedure_count, 0.9) OVER() AS p90_value
  FROM
    procedure_counts
  LIMIT 1
),

-- Combine sepsis and non-sepsis groups for comparison
comparison_groups AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.hospital_los_hours,
    p.hospital_expire_flag,
    CASE WHEN s.subject_id IS NOT NULL THEN 'Sepsis' ELSE 'Control' END AS group_type,
    pc.distinct_procedure_count
  FROM
    patient_base p
  LEFT JOIN
    sepsis_patients s
  ON
    p.subject_id = s.subject_id
    AND p.hadm_id = s.hadm_id
  LEFT JOIN
    procedure_counts pc
  ON
    p.subject_id = pc.subject_id
    AND p.hadm_id = pc.hadm_id
  WHERE
    EXISTS (
      SELECT 1
      FROM first_icu_stay f
      WHERE f.subject_id = p.subject_id
      AND f.hadm_id = p.hadm_id
      AND f.icu_stay_rank = 1
    )
)

-- Final results
SELECT
  group_type,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(hospital_los_hours) AS avg_hospital_los_hours,
  SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_percentage,
  AVG(distinct_procedure_count) AS avg_distinct_procedures,
  (SELECT p90_value FROM percentile_90) AS p90_distinct_procedures
FROM
  comparison_groups
GROUP BY
  group_type
ORDER BY
  group_type;
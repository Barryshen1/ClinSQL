WITH
-- Get female patients aged 44-54 with AMI
ami_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admission_year,
    a.hospital_expire_flag,
    a.dischtime,
    a.admittime,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS icu_los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
    AND d.icd_code LIKE 'I21.%'
    AND i.intime = (
      SELECT MIN(intime)
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE hadm_id = a.hadm_id
    )
),

-- Calculate procedure counts within first 72h of ICU stay
procedure_counts AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    -- Count ICU procedures
    COUNT(DISTINCT pe.itemid) AS icu_procedure_count,
    -- Count hospital procedures
    COUNT(DISTINCT CASE WHEN p.icd_code IS NOT NULL THEN p.icd_code END) AS hospital_procedure_count
  FROM
    ami_patients a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON
    a.stay_id = pe.stay_id AND
    pe.starttime BETWEEN a.icu_intime AND TIMESTAMP_ADD(a.icu_intime, INTERVAL 72 HOUR)
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON
    a.hadm_id = p.hadm_id AND
    p.chartdate BETWEEN DATE(a.icu_intime) AND DATE(TIMESTAMP_ADD(a.icu_intime, INTERVAL 72 HOUR))
  GROUP BY
    a.subject_id, a.hadm_id, a.stay_id
),

-- Combine all data with procedure counts
patient_data AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los_days,
    pc.icu_procedure_count + pc.hospital_procedure_count AS total_procedure_count
  FROM
    ami_patients a
  JOIN
    procedure_counts pc ON a.subject_id = pc.subject_id AND a.hadm_id = pc.hadm_id AND a.stay_id = pc.stay_id
),

-- Calculate quartiles
quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    total_procedure_count,
    hospital_los_days,
    hospital_expire_flag,
    NTILE(4) OVER (ORDER BY total_procedure_count) AS quartile
  FROM
    patient_data
)

-- Final aggregation by quartile
SELECT
  quartile,
  COUNT(*) AS n_patients,
  ROUND(AVG(total_procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(hospital_los_days), 2) AS mean_hospital_los_days,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS in_hospital_mortality_percent
FROM
  quartiles
GROUP BY
  quartile
ORDER BY
  quartile;
WITH
-- Get male patients aged 83-93 at admission
patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS admission_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 83 AND 93
),

-- Get first ICU stay per admission
first_icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime,
    s.los AS icu_los,
    ROW_NUMBER() OVER (PARTITION BY s.subject_id, s.hadm_id ORDER BY s.intime) AS icu_stay_seq
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    patient_admissions pa
    ON s.subject_id = pa.subject_id AND s.hadm_id = pa.hadm_id
  WHERE
    s.intime IS NOT NULL
),
filtered_icu_stays AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    icu_intime,
    icu_outtime,
    icu_los
  FROM
    first_icu_stays
  WHERE
    icu_stay_seq = 1  -- First ICU stay per admission
),

-- Get sepsis patients (using common sepsis ICD-10 codes)
sepsis_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    filtered_icu_stays fis
    ON d.subject_id = fis.subject_id AND d.hadm_id = fis.hadm_id
  WHERE
    d.icd_code IN (
      'A41.9', 'R65.20', 'R65.21', 'A40.9', 'A41.89', 'A41.5', 'A41.51',
      'A41.52', 'A41.59', 'R65.10', 'R65.11'
    )
    AND d.icd_version = 10
),

-- Get procedures in first 72 hours of ICU stay
first_72h_procedures AS (
  SELECT
    fis.subject_id,
    fis.hadm_id,
    fis.stay_id,
    COUNT(DISTINCT
      CASE
        WHEN p.icd_code IS NOT NULL THEN CONCAT(p.icd_code, CAST(p.icd_version AS STRING))
        WHEN pe.itemid IS NOT NULL THEN CAST(pe.itemid AS STRING)
      END
    ) AS procedure_count
  FROM
    filtered_icu_stays fis
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON fis.subject_id = p.subject_id AND fis.hadm_id = p.hadm_id
    AND p.chartdate BETWEEN DATE(fis.icu_intime) AND DATE(DATE_ADD(fis.icu_intime, INTERVAL 3 DAY))
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON fis.subject_id = pe.subject_id AND fis.hadm_id = pe.hadm_id AND fis.stay_id = pe.stay_id
    AND pe.starttime BETWEEN fis.icu_intime AND DATETIME_ADD(fis.icu_intime, INTERVAL 72 HOUR)
  WHERE
    fis.subject_id IN (SELECT subject_id FROM sepsis_patients)
    AND fis.hadm_id IN (SELECT hadm_id FROM sepsis_patients)
  GROUP BY
    fis.subject_id, fis.hadm_id, fis.stay_id
),

-- Calculate quartiles
quartiles AS (
  SELECT
    procedure_count,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM
    first_72h_procedures
),

-- Join all data for final output
final_data AS (
  SELECT
    q.quartile,
    q.procedure_count,
    fis.icu_los,
    pa.hospital_expire_flag
  FROM
    quartiles q
  JOIN
    first_72h_procedures f72
    ON q.procedure_count = f72.procedure_count
  JOIN
    filtered_icu_stays fis
    ON f72.subject_id = fis.subject_id AND f72.hadm_id = fis.hadm_id AND f72.stay_id = fis.stay_id
  JOIN
    patient_admissions pa
    ON fis.subject_id = pa.subject_id AND fis.hadm_id = pa.hadm_id
)

-- Final aggregation by quartile
SELECT
  quartile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(icu_los) AS mean_icu_los_days,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_percentage
FROM
  final_data
GROUP BY
  quartile
ORDER BY
  quartile;
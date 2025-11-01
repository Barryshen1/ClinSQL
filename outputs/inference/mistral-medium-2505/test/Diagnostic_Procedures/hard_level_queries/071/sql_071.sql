WITH
-- Identify female patients aged 50-60 with ICH
ich_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS hospital_los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
),

-- Get first ICU stay for each ICH patient
ich_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS icu_los_hours
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    ich_patients ip
  ON
    i.subject_id = ip.subject_id AND i.hadm_id = ip.hadm_id
  WHERE
    i.intime = (
      SELECT MIN(intime)
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE subject_id = i.subject_id AND hadm_id = i.hadm_id
    )
),

-- Calculate procedure burden in first 72 hours for ICH patients
ich_procedure_burden AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count_72h
  FROM
    ich_icu_stays i
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  ON
    i.subject_id = pe.subject_id AND i.stay_id = pe.stay_id
  WHERE
    pe.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY
    i.subject_id, i.hadm_id, i.stay_id
),

-- Calculate percentiles for ICH patients
ich_percentiles AS (
  SELECT
    PERCENTILE_CONT(procedure_count_72h, 0.25) OVER() AS percentile_25,
    PERCENTILE_CONT(procedure_count_72h, 0.5) OVER() AS percentile_50,
    PERCENTILE_CONT(procedure_count_72h, 0.9) OVER() AS percentile_90,
    MAX(procedure_count_72h) AS max_procedures
  FROM ich_procedure_burden
  LIMIT 1
),

-- General ICU population (excluding ICH patients)
general_icu_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS hospital_los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE
    a.subject_id NOT IN (SELECT subject_id FROM ich_patients)
    AND i.intime = (
      SELECT MIN(intime)
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE subject_id = i.subject_id AND hadm_id = i.hadm_id
    )
),

-- Procedure burden for general ICU patients
general_procedure_burden AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count_72h
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    general_icu_patients g
  ON
    i.subject_id = g.subject_id AND i.hadm_id = g.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  ON
    i.subject_id = pe.subject_id AND i.stay_id = pe.stay_id
  WHERE
    pe.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY
    i.subject_id, i.hadm_id, i.stay_id
),

-- Calculate percentiles for general ICU patients
general_percentiles AS (
  SELECT
    PERCENTILE_CONT(procedure_count_72h, 0.25) OVER() AS percentile_25,
    PERCENTILE_CONT(procedure_count_72h, 0.5) OVER() AS percentile_50,
    PERCENTILE_CONT(procedure_count_72h, 0.9) OVER() AS percentile_90,
    MAX(procedure_count_72h) AS max_procedures
  FROM general_procedure_burden
  LIMIT 1
)

-- Final comparison
SELECT
  'ICH Patients' AS cohort,
  ip.percentile_25,
  ip.percentile_50,
  ip.percentile_90,
  ip.max_procedures,
  AVG(ich.hospital_los_hours) AS avg_hospital_los_hours,
  SUM(CASE WHEN ich.hospital_expire_flag = 1 THEN 1 ELSE 0 END) /
    COUNT(*) AS in_hospital_mortality_rate
FROM
  ich_percentiles ip
CROSS JOIN
  ich_procedure_burden ich
JOIN
  ich_patients ich_p ON ich.subject_id = ich_p.subject_id AND ich.hadm_id = ich_p.hadm_id

UNION ALL

SELECT
  'General ICU Patients' AS cohort,
  gp.percentile_25,
  gp.percentile_50,
  gp.percentile_90,
  gp.max_procedures,
  AVG(general.hospital_los_hours) AS avg_hospital_los_hours,
  SUM(CASE WHEN gip.hospital_expire_flag = 1 THEN 1 ELSE 0 END) /
    COUNT(*) AS in_hospital_mortality_rate
FROM
  general_percentiles gp
CROSS JOIN
  general_procedure_burden general
JOIN
  general_icu_patients gip ON general.subject_id = gip.subject_id AND general.hadm_id = gip.hadm_id;
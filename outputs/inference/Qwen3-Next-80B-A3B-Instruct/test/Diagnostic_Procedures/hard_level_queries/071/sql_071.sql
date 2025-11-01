WITH ich_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND LOWER(dicd.long_title) LIKE '%intracranial hemorrhage%'
),

ich_procedures AS (
  SELECT
    ip.subject_id,
    ip.stay_id,
    COUNT(pe.procedureitemid) AS procedure_count_72h
  FROM ich_patients ip
  LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON ip.stay_id = pe.stay_id
    AND pe.charttime >= ip.intime
    AND pe.charttime <= TIMESTAMP_ADD(ip.intime, INTERVAL 72 HOUR)
  GROUP BY ip.subject_id, ip.stay_id
),

general_icu AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND NOT EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
        ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%intracranial hemorrhage%'
    )
),

general_procedures AS (
  SELECT
    gi.subject_id,
    gi.stay_id,
    COUNT(pe.procedureitemid) AS procedure_count_72h
  FROM general_icu gi
  LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON gi.stay_id = pe.stay_id
    AND pe.charttime >= gi.intime
    AND pe.charttime <= TIMESTAMP_ADD(gi.intime, INTERVAL 72 HOUR)
  GROUP BY gi.subject_id, gi.stay_id
),

ich_summary AS (
  SELECT
    PERCENTILE_CONT(procedure_count_72h, 0.25) OVER() AS p25_procedures_ich,
    PERCENTILE_CONT(procedure_count_72h, 0.50) OVER() AS p50_procedures_ich,
    PERCENTILE_CONT(procedure_count_72h, 0.90) OVER() AS p90_procedures_ich,
    MAX(procedure_count_72h) OVER() AS max_procedures_ich,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days_ich,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate_ich
  FROM ich_patients ip
  LEFT JOIN ich_procedures iproc ON ip.subject_id = iproc.subject_id
),

general_summary AS (
  SELECT
    PERCENTILE_CONT(procedure_count_72h, 0.25) OVER() AS p25_procedures_general,
    PERCENTILE_CONT(procedure_count_72h, 0.50) OVER() AS p50_procedures_general,
    PERCENTILE_CONT(procedure_count_72h, 0.90) OVER() AS p90_procedures_general,
    MAX(procedure_count_72h) OVER() AS max_procedures_general,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days_general,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate_general
  FROM general_icu gi
  LEFT JOIN general_procedures giproc ON gi.subject_id = giproc.subject_id
)

SELECT
  i.p25_procedures_ich,
  i.p50_procedures_ich,
  i.p90_procedures_ich,
  i.max_procedures_ich,
  i.avg_los_days_ich,
  i.mortality_rate_ich,
  g.p25_procedures_general,
  g.p50_procedures_general,
  g.p90_procedures_general,
  g.max_procedures_general,
  g.avg_los_days_general,
  g.mortality_rate_general
FROM ich_summary i
CROSS JOIN general_summary g
LIMIT 1;
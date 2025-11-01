WITH asthma_admissions AS (
  -- Find admissions with asthma ICD codes (ICD-9: 493.*, ICD-10: J45.*)
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      (d.icd_version = 9 AND d.icd_code LIKE '493%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'J45%')
    )
),
cohort AS (
  -- Select male ICU stays aged 77-87 with asthma admission
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN asthma_admissions ast
    ON icu.subject_id = ast.subject_id AND icu.hadm_id = ast.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 77 AND 87
),
procedure_counts AS (
  -- Count ICU procedures in first 72h of each ICU stay
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.anchor_age,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COUNT(*) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime >= c.intime
    AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id, c.intime, c.outtime,
    c.anchor_age, c.admittime, c.dischtime, c.hospital_expire_flag
),
quartiles AS (
  -- Assign quartile based on procedure count
  SELECT
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS procedure_quartile,
    SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, SECOND), 86400) AS hospital_los_days
  FROM procedure_counts
)
SELECT
  procedure_quartile,
  COUNT(*) AS n_stays,
  ROUND(AVG(procedure_count),2) AS mean_procedure_count,
  ROUND(AVG(hospital_los_days),2) AS mean_hospital_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)),4) AS mean_hospital_mortality
FROM quartiles
GROUP BY procedure_quartile
ORDER BY procedure_quartile;
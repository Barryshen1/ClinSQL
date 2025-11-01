WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 53 AND 63
    AND p.gender = 'F'
),
sepsis_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_version = 10
    AND (
      (d.icd_code LIKE 'A41%' OR d.icd_code = 'A409')
      OR d.icd_code = 'R6520'
      OR d.icd_code = 'R6521'
    )
),
all_age_matched AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.hadm_id,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    CASE WHEN sd.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_sepsis
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON a.hadm_id = i.hadm_id
  LEFT JOIN sepsis_diagnoses sd
    ON a.hadm_id = sd.hadm_id
  WHERE p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 53 AND 63
),
procedure_counts AS (
  SELECT
    i.stay_id,
    COUNT(pv.itemid) AS procedure_count
  FROM all_age_matched i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pv
    ON i.stay_id = pv.stay_id
    AND pv.starttime >= i.intime
    AND pv.starttime < DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY i.stay_id
),
stay_summary AS (
  SELECT
    i.stay_id,
    i.has_sepsis,
    i.los,
    i.hospital_expire_flag,
    COALESCE(pc.procedure_count, 0) AS procedure_count
  FROM all_age_matched i
  LEFT JOIN procedure_counts pc
    ON i.stay_id = pc.stay_id
),
group_stats AS (
  SELECT
    CASE WHEN has_sepsis = 1 THEN 'Sepsis' ELSE 'Control' END AS patient_group,
    APPROX_QUANTILES(procedure_count, 1000)[OFFSET(750)] AS proc_75th,
    APPROX_QUANTILES(procedure_count, 1000)[OFFSET(900)] AS proc_90th,
    AVG(los) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hosp_mortality_rate
  FROM stay_summary
  GROUP BY has_sepsis
)
SELECT
  patient_group,
  proc_75th,
  proc_90th,
  avg_los,
  hosp_mortality_rate
FROM group_stats
ORDER BY patient_group;
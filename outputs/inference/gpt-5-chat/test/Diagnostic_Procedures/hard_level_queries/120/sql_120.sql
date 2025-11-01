WITH cohort AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    pat.gender,
    pat.anchor_age,
    ie.intime,
    ie.outtime,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 74 AND 84
    -- First ICU stay only
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ie.subject_id ORDER BY ie.intime) = 1
),
ugi_bleed AS (
  SELECT DISTINCT c.*
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON c.hadm_id = di.hadm_id
  WHERE (
    -- ICD-9 codes for Upper GI hemorrhage
    (di.icd_version = 9 AND (
        di.icd_code LIKE '578%' OR
        di.icd_code LIKE '4560%' OR di.icd_code LIKE '4562%' OR
        di.icd_code LIKE '531%' OR di.icd_code LIKE '532%' OR
        di.icd_code LIKE '533%' OR di.icd_code LIKE '534%'
    ))
    OR
    -- ICD-10 codes for Upper GI hemorrhage
    (di.icd_version = 10 AND (
        di.icd_code LIKE 'K25%' OR di.icd_code LIKE 'K26%' OR
        di.icd_code LIKE 'K27%' OR di.icd_code LIKE 'K28%' OR
        di.icd_code LIKE 'I85%' OR
        di.icd_code LIKE 'K92%'
    ))
  )
),
proc_counts AS (
  SELECT
    u.subject_id,
    u.hadm_id,
    COUNT(*) AS procedure_count
  FROM ugi_bleed u
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON u.hadm_id = pi.hadm_id
    AND pi.chartdate >= DATE(u.intime)
    AND pi.chartdate <= DATE(u.intime + INTERVAL 72 HOUR)
  GROUP BY u.subject_id, u.hadm_id
),
cohort_with_counts AS (
  SELECT
    u.subject_id,
    u.hadm_id,
    u.stay_id,
    u.anchor_age,
    u.gender,
    u.admittime,
    u.dischtime,
    u.hospital_expire_flag,
    u.intime,
    COALESCE(pc.procedure_count,0) AS procedure_count,
    TIMESTAMP_DIFF(u.dischtime, u.admittime, DAY) AS hospital_los
  FROM ugi_bleed u
  LEFT JOIN proc_counts pc
    ON u.subject_id = pc.subject_id AND u.hadm_id = pc.hadm_id
),
quartiled AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM cohort_with_counts
)
SELECT
  quartile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(hospital_los) AS mean_hospital_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hosp_mortality_rate
FROM quartiled
GROUP BY quartile
ORDER BY quartile;
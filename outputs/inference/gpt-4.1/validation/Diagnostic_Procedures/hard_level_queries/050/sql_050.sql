WITH ami_admissions AS (
  -- Identify admissions with AMI diagnosis (ICD-9 410.x or ICD-10 I21.x/I22.x)
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (
    (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^410'))
    OR
    (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I21|^I22'))
  )
),
cohort AS (
  -- Join patients, admissions, icustays, filter for male, age 76-86, AMI, and get ICU stay info
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    pat.gender,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN ami_admissions ami
    ON icu.subject_id = ami.subject_id AND icu.hadm_id = ami.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 76 AND 86
),
proc_counts AS (
  -- Count distinct procedures in first 24h of ICU stay
  SELECT
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    c.intime,
    c.outtime,
    c.los,
    c.anchor_age,
    c.gender,
    c.hospital_expire_flag,
    COUNT(DISTINCT p.icd_code) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON c.subject_id = p.subject_id
    AND c.hadm_id = p.hadm_id
    AND p.chartdate >= c.intime
    AND p.chartdate < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY
    c.stay_id, c.subject_id, c.hadm_id, c.intime, c.outtime, c.los, c.anchor_age, c.gender, c.hospital_expire_flag
),
quartiles AS (
  -- Assign quartiles based on procedure_count
  SELECT
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS procedure_quartile
  FROM proc_counts
)
SELECT
  procedure_quartile AS quartile,
  COUNT(*) AS n_stays,
  ROUND(AVG(procedure_count),2) AS mean_procedure_count,
  ROUND(AVG(los),2) AS mean_icu_los,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*),2) AS hospital_mortality_percent
FROM quartiles
GROUP BY procedure_quartile
ORDER BY procedure_quartile;
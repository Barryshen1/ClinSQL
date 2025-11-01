WITH sepsis_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%sepsis%'
     OR icd_code IN ('99592', 'A419', 'A418', 'A415', 'A410', 'A411', 'A412', 'A413', 'A414', 'A4189', 'A419')
),
first_icu_stays AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ROW_NUMBER() OVER (PARTITION BY ie.subject_id ORDER BY ie.intime) AS stay_order
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
),
patients_filtered AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    EXTRACT(YEAR FROM MIN(ie.intime)) AS cohort_year,
    FLOOR((EXTRACT(YEAR FROM MIN(ie.intime)) - p.anchor_year) + p.anchor_age) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  GROUP BY p.subject_id, p.gender, p.anchor_age, p.anchor_year
  HAVING age_at_icu BETWEEN 66 AND 76
    AND p.gender = 'F'
),
sepsis_labels AS (
  SELECT DISTINCT
    de.subject_id,
    TRUE AS has_sepsis
  FROM first_icu_stays fis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` de ON fis.hadm_id = de.hadm_id
  INNER JOIN sepsis_codes sc ON de.icd_code = sc.icd_code AND de.icd_version = sc.icd_version
  WHERE fis.stay_order = 1
),
cohort AS (
  SELECT 
    pf.subject_id,
    pf.age_at_icu,
    fis.stay_id,
    fis.intime,
    fis.outtime,
    COALESCE(sl.has_sepsis, FALSE) AS has_sepsis,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS hosp_los_days
  FROM patients_filtered pf
  INNER JOIN first_icu_stays fis ON pf.subject_id = fis.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON fis.hadm_id = adm.hadm_id
  LEFT JOIN sepsis_labels sl ON pf.subject_id = sl.subject_id
  WHERE fis.stay_order = 1
),
procedures_in_48h AS (
  SELECT
    co.subject_id,
    co.has_sepsis,
    co.hospital_expire_flag,
    co.hosp_los_days,
    COUNT(DISTINCT pe.itemid) AS distinct_proc_count
  FROM cohort co
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON co.stay_id = pe.stay_id
    AND pe.starttime >= co.intime
    AND pe.starttime <= co.intime + INTERVAL 48 HOUR
  GROUP BY co.subject_id, co.has_sepsis, co.hospital_expire_flag, co.hosp_los_days
),
summary_stats AS (
  SELECT
    CASE WHEN has_sepsis THEN 'Sepsis' ELSE 'Control' END AS group_label,
    APPROX_QUANTILES(distinct_proc_count, 1000)[OFFSET(900)] AS proc_90th,
    AVG(hosp_los_days) AS avg_hosp_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM procedures_in_48h
  GROUP BY has_sepsis
)
SELECT 
  group_label,
  proc_90th,
  avg_hosp_los_days,
  mortality_rate
FROM summary_stats
ORDER BY group_label;
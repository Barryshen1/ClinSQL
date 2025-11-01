WITH age_matched_male_icu AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    icu.stay_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.subject_id = icu.subject_id
    AND a.hadm_id = icu.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
),

ami_flags AS (
  SELECT DISTINCT diag.subject_id, diag.hadm_id, 1 AS ami_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code
    AND diag.icd_version = d.icd_version
  WHERE (
      (diag.icd_version = 9 AND diag.icd_code LIKE '410%') OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%') OR
      LOWER(d.long_title) LIKE '%acute myocardial infarction%'
  )
),

procedures_72h AS (
  SELECT
    stay.subject_id,
    stay.hadm_id,
    stay.stay_id,
    COUNT(DISTINCT pe.itemid) AS distinct_proc_count_72h
  FROM age_matched_male_icu stay
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON stay.subject_id = pe.subject_id
    AND stay.hadm_id = pe.hadm_id
    AND stay.stay_id = pe.stay_id
    AND pe.starttime >= stay.intime
    AND pe.starttime <= DATETIME_ADD(stay.intime, INTERVAL 72 HOUR)
  GROUP BY stay.subject_id, stay.hadm_id, stay.stay_id
),

combined AS (
  SELECT
    cohort.subject_id,
    cohort.hadm_id,
    cohort.stay_id,
    proc.distinct_proc_count_72h,
    IF(ami.ami_flag = 1, 1, 0) AS ami_flag,
    cohort.admittime,
    cohort.dischtime,
    TIMESTAMP_DIFF(cohort.dischtime, cohort.admittime, HOUR)/24.0 AS hosp_los_days,
    cohort.hospital_expire_flag
  FROM age_matched_male_icu cohort
  LEFT JOIN procedures_72h proc
    ON cohort.subject_id = proc.subject_id
    AND cohort.hadm_id = proc.hadm_id
    AND cohort.stay_id = proc.stay_id
  LEFT JOIN ami_flags ami
    ON cohort.subject_id = ami.subject_id
    AND cohort.hadm_id = ami.hadm_id
)

SELECT
  metric_group,
  COUNT(*) AS n_patients,
  AVG(hosp_los_days) AS mean_hosp_los_days,
  AVG(hospital_expire_flag) AS mortality_rate,
  CASE 
    WHEN metric_group = 'AMI' 
    THEN APPROX_QUANTILES(distinct_proc_count_72h, 100)[OFFSET(90)] 
  END AS p90_diag_intensity
FROM (
  SELECT *,
    CASE WHEN ami_flag = 1 THEN 'AMI' ELSE 'Non-AMI' END AS metric_group
  FROM combined
) sub
GROUP BY metric_group
ORDER BY metric_group;
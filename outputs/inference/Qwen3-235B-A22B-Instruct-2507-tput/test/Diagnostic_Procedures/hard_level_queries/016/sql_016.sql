WITH pneumonia_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%pneumonia%'
    AND icd_version = 10
),
patients_with_pneumonia AS (
  SELECT DISTINCT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN pneumonia_codes pc
    ON di.icd_code = pc.icd_code AND di.icd_version = 10
),
first_icu_stay AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los AS icu_los,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hospital_expire_flag,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit,
    -- Rank ICU stays by intime per patient
    RANK() OVER (PARTITION BY ie.subject_id ORDER BY ie.intime) AS icu_stay_rank
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ie.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN patients_with_pneumonia pwp
    ON ie.subject_id = pwp.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 88 AND 98
),
target_stays AS (
  SELECT *
  FROM first_icu_stay
  WHERE icu_stay_rank = 1
),
procedure_counts_72h AS (
  SELECT 
    ts.stay_id,
    ts.icu_los,
    ts.hospital_expire_flag,
    COUNT(pe.stay_id) AS procedure_count_72h
  FROM target_stays ts
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON ts.stay_id = pe.stay_id
    AND pe.starttime >= ts.intime
    AND pe.starttime <= DATETIME_ADD(ts.intime, INTERVAL 72 HOUR)
    AND pe.starttime IS NOT NULL
  GROUP BY ts.stay_id, ts.icu_los, ts.hospital_expire_flag
),
quintiles AS (
  SELECT 
    procedure_count_72h,
    icu_los,
    hospital_expire_flag,
    NTILE(5) OVER (ORDER BY procedure_count_72h) AS quintile
  FROM procedure_counts_72h
)
SELECT 
  quintile,
  AVG(procedure_count_72h) AS avg_procedure_count,
  AVG(icu_los) AS avg_icu_los_days,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct
FROM quintiles
GROUP BY quintile
ORDER BY quintile;
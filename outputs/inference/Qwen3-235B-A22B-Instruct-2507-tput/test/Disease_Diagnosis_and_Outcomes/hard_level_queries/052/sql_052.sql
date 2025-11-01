WITH patients_age_gender AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.dod,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 75 AND 85
),

copd_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id,
    di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_version = 10
    AND d.icd_code LIKE 'J44%'
),

copd_cohort AS (
  SELECT
    pa.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    pa.dod,
    -- Check 90-day mortality
    CASE
      WHEN pa.dod IS NOT NULL AND pa.dod <= DATETIME_ADD(a.admittime, INTERVAL 90 DAY)
        THEN 1
      WHEN a.deathtime IS NOT NULL AND a.deathtime <= DATETIME_ADD(a.admittime, INTERVAL 90 DAY)
        THEN 1
      ELSE 0
    END AS mortality_90day,
    -- ICU admission during stay
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_admission,
    -- Hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) AS los_days
  FROM patients_age_gender pa
  INNER JOIN copd_diagnoses cd
    ON pa.subject_id = cd.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON pa.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON a.hadm_id = i.hadm_id
)

-- Final selection to complete the query (example: select all from cohort)
SELECT * FROM copd_cohort;
WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 58 AND 68
),

ami_chest_pain_codes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (
    -- AMI ICD-10 codes: I21.*, I22.*
    (di.icd_version = 10 AND di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%')
    OR
    -- Chest pain: R07.2, R07.9
    (di.icd_version = 10 AND di.icd_code IN ('R072', 'R079')) -- Note: ICD-10 codes stored without dot
  )
),

troponin_t_values AS (
  SELECT
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin%t%'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= (SELECT MIN(admittime) FROM `physionet-data.mimiciv_3_1_hosp`.admissions a WHERE a.hadm_id = le.hadm_id)
),

first_troponin AS (
  SELECT
    hadm_id,
    valuenum AS first_troponin_t
  FROM troponin_t_values
  WHERE rn = 1
),

cohort AS (
  SELECT
    pa.hadm_id,
    pa.hospital_expire_flag,
    pa.age_at_admission
  FROM patient_admissions pa
  INNER JOIN ami_chest_pain_codes acp
    ON pa.hadm_id = acp.hadm_id
  INNER JOIN first_troponin ft
    ON pa.hadm_id = ft.hadm_id
  WHERE ft.first_troponin_t > 0.04
)

SELECT
  COUNT(*) AS total_admissions,
  SUM(hospital_expire_flag) AS deaths,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(age_at_admission) AS mean_age,
  MIN(age_at_admission) AS min_age,
  MAX(age_at_admission) AS max_age
FROM cohort;
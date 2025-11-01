WITH HF_Admissions AS (
  -- Select admissions for patients with Heart Failure diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I50%' -- ICD-9 codes for Heart Failure
    OR d.icd_code LIKE 'I11%' -- ICD-10 codes for Heart Failure (Hypertensive Heart Disease with HF)
    OR d.icd_code LIKE 'I13%' -- ICD-10 codes for Heart Failure (Other Hypertensive Heart Disease with HF)
    OR d.icd_code LIKE 'I09%' -- ICD-10 codes for Heart Failure (Heart disease with HF)
    OR d.icd_code LIKE 'J81%' -- ICD-10 codes for Heart Failure (Acute pulmonary edema)
    OR d.icd_code LIKE 'R06%' -- ICD-10 codes for Heart Failure (Dyspnea)
    OR d.icd_code LIKE '428%' -- ICD-9 codes for Heart Failure
  GROUP BY
    a.subject_id,
    a.hadm_id
),
Male_HF_Admissions AS (
  -- Filter for male patients within the specified age range
  SELECT
    hfa.subject_id,
    hfa.hadm_id,
    hfa.admittime,
    hfa.dischtime,
    hfa.deathtime,
    hfa.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM HF_Admissions AS hfa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON hfa.subject_id = p.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 77 AND 87
),
ICU_Admissions AS (
  -- Identify ICU admissions and calculate LOS
  SELECT
    maha.subject_id,
    maha.hadm_id,
    maha.admittime,
    maha.dischtime,
    maha.deathtime,
    maha.hospital_expire_flag,
    maha.gender,
    maha.anchor_age,
    CASE
      WHEN it.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_status,
    -- Calculate LOS in days
    CAST(TIMESTAMP_DIFF(maha.dischtime, maha.admittime, DAY) AS INT64) AS los
  FROM Male_HF_Admissions AS maha
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS it
    ON maha.subject_id = it.subject_id AND maha.hadm_id = it.hadm_id
),
LOS_Groups AS (
  -- Group;
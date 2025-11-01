WITH HF_Patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 80 AND 90
    AND a.hospital_expire_flag = 1
), HF_Diagnoses AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I50%' -- ICD-10 codes for Heart Failure
), HF_Admissions AS (
  SELECT
    hf_p.subject_id,
    hf_p.hadm_id,
    hf_p.admittime,
    hf_p.dischtime,
    hf_p.deathtime,
    hf_p.hospital_expire_flag
  FROM HF_Patients AS hf_p
  INNER JOIN HF_Diagnoses AS hf_d
    ON hf_p.subject_id = hf_d.subject_id AND hf_p.hadm_id = hf_d.hadm_id
), Mortality_Analysis AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    -- Calculate Length of Stay (LOS)
    TIMESTAMP_DIFF(dischtime, admitime, DAY) AS los
  FROM HF_Admissions
), Mortality_By_LOS AS (
  SELECT
    hadm_id,
    subject_id,
    los,
    hospital_expire_flag,
    CASE
      WHEN los BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN los >= 8 THEN '>=8 days'
      ELSE 'Other'
    END AS los_category
  FROM Mortality_Analysis
), Mortality_Summary AS (
  SELECT
    los_category,
    COUNT(hadm_id) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    -- Calculate mortality rate as a percentage
    SUM(hospital_expire_flag) / COUNT(hadm_id) AS mortality_rate,
    -- Calculate median time to death only for those who died
    PERCENTILE_CONT(TIMESTAMP_DIFF(deathtime, admitime, DAY), 0.5) OVER (PARTITION BY los_category) AS median_time_to_death
  FROM Mortality_By_LOS
  WHERE hospital_expire_flag = 1
  GROUP BY
    los_category
)
SELECT
  los_category,
  total_patients,
  deaths,
  mortality_rate,
  median_time_to_death
FROM Mortality_Summary
ORDER BY
  CASE
    WHEN los_category = '1-3 days' THEN 1;
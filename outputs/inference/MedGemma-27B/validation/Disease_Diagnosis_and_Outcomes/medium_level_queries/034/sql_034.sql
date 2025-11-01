WITH PatientDiagnosis AS (
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
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND d.icd_code LIKE 'I50%' -- Heart failure codes (I50.1, I50.2, I50.3, I50.4, I50.9)
    AND d.seq_num = 1 -- Assuming the first diagnosis is the primary one
),
PatientLOS AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    -- Calculate Length of Stay (LOS)
    -- If patient died in hospital, LOS is time from admission to death
    -- Otherwise, LOS is time from admission to discharge
    CASE
      WHEN hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(deathtime, admittime, DAY)
      ELSE TIMESTAMP_DIFF(dischtime, admittime, DAY)
    END AS los
  FROM PatientDiagnosis
)
SELECT
  CASE
    WHEN los < 8 THEN 'LOS < 8 days'
    ELSE 'LOS >= 8 days'
  END AS los_category,
  COUNT(DISTINCT hadm_id) AS admission_count,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT hadm_id) AS mortality_rate_percent,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(deathtime, admittime, DAY) ELSE NULL END) AS median_time_to_death_days
FROM PatientLOS
GROUP BY
  los_category
ORDER BY
  los_category;
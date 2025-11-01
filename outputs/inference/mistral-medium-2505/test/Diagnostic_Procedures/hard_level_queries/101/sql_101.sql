WITH
-- Define age range and gender
age_gender_filter AS (
  SELECT
    subject_id,
    hadm_id,
    anchor_age,
    anchor_year,
    gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 88 AND 98
),

-- Get COPD exacerbation patients
copd_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    age_gender_filter a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN (
      'J44.0', 'J44.1', 'J44.9', 'J43.9', 'J42', 'J41.0', 'J41.1', 'J41.8', 'J40'
    )
    AND d.icd_version = 10
),

-- Get first ICU stay for each patient
first_icu_stay AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime AS icu_intime,
    outtime,
    los
  FROM (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      intime,
      outtime,
      los,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),

-- Get procedures within first 72 hours of ICU admission
early_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    COUNT(DISTINCT p.icd_code) AS distinct_procedures
  FROM
    first_icu_stay f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON f.subject_id = p.subject_id AND f.hadm_id = p.hadm_id
  WHERE
    p.chartdate BETWEEN f.icu_intime AND DATETIME_ADD(f.icu_intime, INTERVAL 72 HOUR)
  GROUP BY
    p.subject_id, p.hadm_id, p.stay_id

  UNION ALL

  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    COUNT(DISTINCT p.itemid) AS distinct_procedures
  FROM
    first_icu_stay f
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON f.subject_id = p.subject_id AND f.hadm_id = p.hadm_id AND f.stay_id = p.stay_id
  WHERE
    p.starttime BETWEEN f.icu_intime AND DATETIME_ADD(f.icu_intime, INTERVAL 72 HOUR)
  GROUP BY
    p.subject_id, p.hadm_id, p.stay_id
),

-- Get age-matched non-COPD patients
non_copd_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    age_gender_filter a
  WHERE
    a.subject_id NOT IN (SELECT subject_id FROM copd_patients)
),

-- Get first ICU stay for non-COPD patients
non_copd_icu_stay AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime AS icu_intime,
    outtime,
    los
  FROM (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      intime,
      outtime,
      los,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE
      subject_id IN (SELECT subject_id FROM non_copd_patients)
  )
  WHERE rn = 1
),

-- Get mortality for both groups
mortality AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE
    a.subject_id IN (
      SELECT subject_id FROM copd_patients
      UNION
      SELECT subject_id FROM non_copd_patients
    )
),

-- Get procedures for non-COPD patients
non_copd_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    COUNT(DISTINCT p.icd_code) AS distinct_procedures
  FROM
    non_copd_icu_stay f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON f.subject_id = p.subject_id AND f.hadm_id = p.hadm_id
  WHERE
    p.chartdate BETWEEN f.icu_intime AND DATETIME_ADD(f.icu_intime, INTERVAL 72 HOUR)
  GROUP BY
    p.subject_id, p.hadm_id, p.stay_id

  UNION ALL

  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    COUNT(DISTINCT p.itemid) AS distinct_procedures
  FROM
    non_copd_icu_stay f
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON f.subject_id = p.subject_id AND f.hadm_id = p.hadm_id AND f.stay_id = p.stay_id
  WHERE
    p.starttime BETWEEN f.icu_intime AND DATETIME_ADD(f.icu_intime, INTERVAL 72 HOUR)
  GROUP BY
    p.subject_id, p.hadm_id, p.stay_id
)

-- Final results
SELECT
  'COPD Exacerbation' AS patient_group,
  PERCENTILE_CONT(distinct_procedures, 0.75) WITHIN GROUP (ORDER BY distinct_procedures) AS percentile_75_procedures,
  AVG(los) AS mean_icu_los,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality_rate
FROM
  early_procedures e
JOIN
  first_icu_stay f ON e.subject_id = f.subject_id AND e.hadm_id = f.hadm_id AND e.stay_id = f.stay_id
JOIN
  mortality m ON e.subject_id = m.subject_id AND e.hadm_id = m.hadm_id
WHERE
  e.subject_id IN (SELECT subject_id FROM copd_patients)

UNION ALL

SELECT
  'Age-Matched Non-COPD' AS patient_group,
  PERCENTILE_CONT(distinct_procedures, 0.75) WITHIN GROUP (ORDER BY distinct_procedures) AS percentile_75_procedures,
  AVG(los) AS mean_icu_los,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality_rate
FROM
  non_copd_procedures e
JOIN
  non_copd_icu_stay f ON e.subject_id = f.subject_id AND e.hadm_id = f.hadm_id AND e.stay_id = f.stay_id
JOIN
  mortality m ON e.subject_id = m.subject_id AND e.hadm_id = m.hadm_id;
WITH PatientCohort AS (
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
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
), SepsisCohort AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.deathtime,
    pc.hospital_expire_flag,
    d.icd_code
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON pc.subject_id = d.subject_id
    AND pc.hadm_id = d.hadm_id
  WHERE
    d.icd_code = 'R65.21' -- Sepsis without organ dysfunction
), MortalityAnalysis AS (
  SELECT
    sc.subject_id,
    sc.hadm_id,
    sc.deathtime,
    sc.hospital_expire_flag,
    -- Calculate Length of Stay (LOS)
    TIMESTAMP_DIFF(sc.dischtime, sc.admittime, DAY) AS los,
    -- Calculate Time to Death
    CASE
      WHEN sc.hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(sc.deathtime, sc.admittime, DAY)
      ELSE NULL
    END AS time_to_death
  FROM SepsisCohort AS sc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON sc.hadm_id = a.hadm_id
), FinalAnalysis AS (
  SELECT
    CASE
      WHEN los < 8 THEN 'LOS < 8 days'
      ELSE 'LOS >= 8 days'
    END AS los_group,
    hospital_expire_flag,
    time_to_death
  FROM MortalityAnalysis
)
SELECT
  los_group,
  hospital_expire_flag,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  -- Calculate mortality rate
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate,
  -- Calculate median time to death
  PERCENTILE_CONT(time_to_death, 0.5) OVER (PARTITION BY los_group, hospital_expire_flag) AS median_time_to_death
FROM FinalAnalysis
WHERE
  hospital_expire_flag = 1 -- Only consider non-survivors for median time to death
GROUP BY
  los_group,
  hospital_expire_flag
ORDER BY
  los_group;
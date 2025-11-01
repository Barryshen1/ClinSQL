WITH sepsis_admissions AS (
  -- Identify admissions with sepsis (excluding septic shock)
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    -- Sepsis codes (ICD-9 and ICD-10)
    (
      (d.icd_version = 9 AND d.icd_code IN ('99591', '99592'))
      OR
      (d.icd_version = 10 AND d.icd_code IN ('A419', 'A410', 'A411', 'A412', 'A413', 'A414', 'A415', 'A418'))
    )
    AND d.hadm_id NOT IN (
      -- Exclude septic shock
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd
      WHERE
        (icd_version = 9 AND icd_code = '78552')
        OR
        (icd_version = 10 AND icd_code IN ('R6520', 'R6521'))
    )
),

eligible_patients AS (
  -- Filter patients by age and gender
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
),

first_icu_stays AS (
  -- Get first ICU stay per hospital admission
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    i.first_careunit,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_icu.icustays i
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
  WHERE
    i.stay_id IN (
      SELECT MIN(stay_id)
      FROM physionet-data.mimiciv_3_1_icu.icustays
      GROUP BY hadm_id
    )
),

final_cohort AS (
  -- Combine all filters
  SELECT
    f.*,
    CASE
      WHEN f.los <= 3 THEN '≤3'
      WHEN f.los > 3 AND f.los <= 6 THEN '4–6'
      WHEN f.los > 6 AND f.los <= 10 THEN '7–10'
      ELSE '>10'
    END AS los_group,
    DATE_DIFF(f.dischtime, f.admittime, DAY) AS hosp_los_days,
    DATE_DIFF(f.deathtime, f.admittime, DAY) AS days_to_death
  FROM
    first_icu_stays f
  JOIN
    sepsis_admissions s
    ON f.hadm_id = s.hadm_id
  JOIN
    eligible_patients p
    ON f.subject_id = p.subject_id
)

SELECT
  los_group,
  first_careunit AS day1_icu_status,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
  APPROX_QUANTILES(days_to_death, 2)[OFFSET(1)] AS median_days_to_death
FROM
  final_cohort
WHERE
  hospital_expire_flag = 1 OR deathtime IS NULL
GROUP BY
  los_group,
  first_careunit
ORDER BY
  los_group,
  first_careunit;
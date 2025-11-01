WITH
-- 1. Get all admissions for females age 66-76
female_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
),

-- 2. Identify AMI admissions
ami_admissions AS (
  SELECT DISTINCT
    fa.*
  FROM
    female_admissions fa
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON fa.hadm_id = d.hadm_id
  WHERE
    (
      -- ICD-10 AMI: I21, I22
      (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
      -- ICD-9 AMI: 410
      OR (d.icd_version = 9 AND d.icd_code LIKE '410%')
    )
),

-- 3. Exclude admissions with shock or respiratory failure diagnosis (any seq_num)
exclude_shock_resp AS (
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (
      -- Shock: ICD-10 R57, ICD-9 785.5
      (icd_version = 10 AND icd_code LIKE 'R57%')
      OR (icd_version = 9 AND icd_code LIKE '7855%')
      -- Respiratory failure: ICD-10 J96, ICD-9 518.81, 518.84
      OR (icd_version = 10 AND icd_code LIKE 'J96%')
      OR (icd_version = 9 AND (icd_code LIKE '51881%' OR icd_code LIKE '51884%'))
    )
),

-- 4. Final cohort: AMI admissions, female, age 66-76, no shock/resp failure
final_cohort AS (
  SELECT
    aa.*,
    DATETIME_DIFF(aa.dischtime, aa.admittime, DAY) AS los_days,
    CASE
      WHEN aa.admission_type = 'EMERGENCY' THEN 'Emergent'
      ELSE 'Non-Emergent'
    END AS admit_type_group
  FROM
    ami_admissions aa
  WHERE
    aa.hadm_id NOT IN (SELECT hadm_id FROM exclude_shock_resp)
    AND DATETIME_DIFF(aa.dischtime, aa.admittime, DAY) >= 0
),

-- 5. Bin LOS
binned_cohort AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '8+'
      ELSE NULL
    END AS los_bin
  FROM
    final_cohort
  WHERE
    los_days IS NOT NULL
)

-- 6. Aggregate results
SELECT
  los_bin,
  admit_type_group,
  COUNT(*) AS n_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_percent,
  -- Median time-to-death among those who died in hospital
  APPROX_QUANTILES(
    DATETIME_DIFF(deathtime, admittime, DAY),
    2
  )[OFFSET(1)] AS median_time_to_death_days
FROM
  binned_cohort
WHERE
  los_bin IS NOT NULL
GROUP BY
  los_bin,
  admit_type_group
ORDER BY
  los_bin,
  admit_type_group;
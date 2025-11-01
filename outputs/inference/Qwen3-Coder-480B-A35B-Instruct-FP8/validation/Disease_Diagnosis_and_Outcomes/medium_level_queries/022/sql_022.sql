WITH sepsis_admissions AS (
  -- Identify admissions with sepsis but no septic shock
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%sepsis%'
    AND LOWER(dd.long_title) NOT LIKE '%shock%'
),

eligible_patients AS (
  -- Filter patients by age and gender
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    sa.hadm_id,
    sa.admittime,
    sa.dischtime,
    sa.deathtime,
    sa.hospital_expire_flag,
    sa.los
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    sepsis_admissions sa
    ON p.subject_id = sa.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
),

icu_day1 AS (
  -- Determine ICU status on day 1 of admission
  SELECT DISTINCT
    ep.hadm_id,
    CASE
      WHEN i.stay_id IS NOT NULL THEN 1
      ELSE 0
    END AS day1_icu
  FROM
    eligible_patients ep
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON ep.hadm_id = i.hadm_id
    AND i.intime BETWEEN ep.admittime AND DATETIME_ADD(ep.admittime, INTERVAL 1 DAY)
),

final_cohort AS (
  SELECT
    ep.*,
    id.day1_icu
  FROM
    eligible_patients ep
  JOIN
    icu_day1 id
    ON ep.hadm_id = id.hadm_id
)

SELECT
  day1_icu,
  CASE
    WHEN los <= 7 THEN 'LOS ≤7'
    ELSE 'LOS >7'
  END AS los_group,
  COUNT(*) AS n_patients,
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los
FROM
  final_cohort
GROUP BY
  day1_icu,
  los_group
ORDER BY
  day1_icu,
  los_group;
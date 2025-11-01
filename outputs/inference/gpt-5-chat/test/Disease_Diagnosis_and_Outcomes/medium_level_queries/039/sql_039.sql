WITH ami_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
    (d.icd_version = 9 AND d.icd_code LIKE '410%')
    OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
  )
),
exclude_shock_resp AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (
    -- Shock codes
    (d.icd_version = 9 AND d.icd_code LIKE '7855%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'R57%')
    -- Respiratory failure codes
    OR (d.icd_version = 9 AND (
         d.icd_code LIKE '51881%' OR d.icd_code LIKE '51882%' OR d.icd_code LIKE '51884%')
       )
    OR (d.icd_version = 10 AND d.icd_code LIKE 'J96%')
  )
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM ami_admissions ami
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ami.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
    AND a.hadm_id NOT IN (SELECT hadm_id FROM exclude_shock_resp)
),
final AS (
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag,
    CASE
      WHEN admission_type = 'EMERGENCY' THEN 'Emergent'
      ELSE 'Non-Emergent'
    END AS admission_cat,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN 'LOS 1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN 'LOS 4-7'
      WHEN los_days >= 8 THEN 'LOS >=8'
      ELSE 'LOS <1'
    END AS los_cat,
    CASE
      WHEN hospital_expire_flag = 1 THEN DATE_DIFF(deathtime, admittime, DAY)
      ELSE NULL
    END AS ttd_days
  FROM cohort
)
SELECT
  los_cat,
  admission_cat,
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  IFNULL(ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2), 0) AS mortality_percent,
  ROUND(APPROX_QUANTILES(ttd_days, 100)[OFFSET(50)], 1) AS median_time_to_death_days
FROM final
GROUP BY los_cat, admission_cat
ORDER BY los_cat, admission_cat;
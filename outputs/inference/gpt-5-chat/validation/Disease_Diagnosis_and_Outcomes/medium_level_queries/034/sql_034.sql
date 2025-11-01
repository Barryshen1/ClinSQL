WITH hf_admissions AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    TIMESTAMP_DIFF(adm.deathtime, adm.admittime, DAY) AS time_to_death_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dx.icd_code = dd.icd_code
    AND dx.icd_version = dd.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 70 AND 80
    AND LOWER(dd.long_title) LIKE '%heart failure%'
)
SELECT
  CASE WHEN los_days < 8 THEN '<8 days' ELSE '>=8 days' END AS los_category,
  COUNT(*) AS admission_count,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS mortality_rate_percent,
  ROUND(
    APPROX_QUANTILES(
      IF(hospital_expire_flag = 1, time_to_death_days, NULL), 
      100
    )[OFFSET(50)],
    2
  ) AS median_time_to_death_days_non_survivors
FROM hf_admissions
WHERE los_days IS NOT NULL
GROUP BY los_category
ORDER BY los_category;
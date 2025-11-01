WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 2 THEN '1-2'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 3 AND 5 THEN '3-5'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 6 AND 9 THEN '6-9'
      ELSE '>=10'
    END AS los_category,
    MAX(CASE WHEN i.intime <= DATETIME_ADD(a.admittime, INTERVAL 1 DAY) THEN 1 ELSE 0 END) AS day1_icu,
    MAX(CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_admitted,
    MAX(CASE WHEN did.long_title LIKE '%upper gastrointestinal hemorrhage%' THEN 1 ELSE 0 END) AS upper_gi,
    MAX(CASE WHEN did.long_title LIKE '%lower gastrointestinal hemorrhage%' THEN 1 ELSE 0 END) AS lower_gi
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND (
      did.long_title LIKE '%upper gastrointestinal hemorrhage%'
      OR did.long_title LIKE '%lower gastrointestinal hemorrhage%'
    )
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag, p.anchor_age, p.gender
),
classified AS (
  SELECT *,
    CASE
      WHEN upper_gi = 1 AND lower_gi = 0 THEN 'Upper GI'
      WHEN lower_gi = 1 AND upper_gi = 0 THEN 'Lower GI'
      WHEN upper_gi = 1 AND lower_gi = 1 THEN 'Both'
      ELSE 'Other'
    END AS bleed_type
  FROM cohort
)
SELECT
  bleed_type,
  los_category,
  day1_icu,
  COUNT(*) AS n_patients,
  AVG(hospital_expire_flag) * 100 AS in_hosp_mortality_pct,
  AVG(icu_admitted) * 100 AS icu_admission_rate_pct
FROM classified
WHERE bleed_type IN ('Upper GI', 'Lower GI')
GROUP BY bleed_type, los_category, day1_icu
ORDER BY bleed_type, los_category, day1_icu;
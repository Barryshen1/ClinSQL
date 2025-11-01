WITH female_icu_admissions AS (
  -- Get female ICU admissions aged 87-97
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    p.dod,
    a.dischtime,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los AS icu_los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN p.dod IS NOT NULL THEN 'Post-discharge death'
      ELSE 'No death recorded'
    END AS death_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND i.intime IS NOT NULL
    AND i.outtime IS NOT NULL
),

-- Get first ICU stay per admission (to avoid duplicates)
first_icu_stay AS (
  SELECT
    subject_id,
    hadm_id,
    death_location,
    icu_los_days,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
  FROM
    female_icu_admissions
)

SELECT
  death_location,
  COUNT(*) AS n,
  ROUND(AVG(icu_los_days), 2) AS mean_los_days,
  ROUND(STDDEV(icu_los_days), 2) AS sd_los_days,
  ROUND(100 * SUM(CASE WHEN icu_los_days < 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_lt_10_days
FROM
  first_icu_stay
WHERE
  rn = 1  -- Only first ICU stay per admission
GROUP BY
  death_location
ORDER BY
  n DESC;
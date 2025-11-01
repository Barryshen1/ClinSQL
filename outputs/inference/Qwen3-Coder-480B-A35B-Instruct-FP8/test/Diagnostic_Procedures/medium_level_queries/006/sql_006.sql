WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN i.hadm_id IS NOT NULL THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_status,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) >= 1 AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) <= 4 THEN '1-4 days'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) >= 5 AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) <= 8 THEN '5-8 days'
    END AS los_group
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE d.icd_code IN ('A41.9', 'R65.20') -- Sepsis codes
    )
    AND a.hadm_id NOT IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE d.icd_code = 'R65.21' -- Exclude septic shock
    )
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),

ultrasound_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS ultrasound_count
  FROM
    physionet-data.mimiciv_3_1_hosp.procedures_icd p
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%ultrasound%'
  GROUP BY
    hadm_id
)

SELECT
  c.icu_status,
  c.los_group,
  COUNT(DISTINCT c.hadm_id) AS patient_count,
  AVG(COALESCE(u.ultrasound_count, 0)) AS mean_ultrasounds_per_admission
FROM
  cohort c
LEFT JOIN
  ultrasound_counts u
  ON c.hadm_id = u.hadm_id
WHERE
  c.los_group IS NOT NULL
GROUP BY
  c.icu_status,
  c.los_group
ORDER BY
  c.icu_status,
  c.los_group;
WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Compute LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime  -- Valid discharge
),

cohort AS (
  SELECT *
  FROM patient_admissions
  WHERE age_at_admission >= 64 AND age_at_admission <= 74
),

discharge_groups AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME IV PROVIDER') THEN 'Home'
      WHEN discharge_location IN (
        'SKILLED NURSING FACILITY', 'SNF', 'REHAB', 'REHAB UNIT', 'LONG TERM CARE HOSPITAL', 'LTACH'
      ) THEN 'SNF/rehab/LTACH'
      ELSE 'Other'
    END AS discharge_group
  FROM cohort
)

SELECT
  discharge_group,
  -- Proportion with LOS >= 7 days
  AVG(CASE WHEN los_days >= 7 THEN 1.0 ELSE 0.0 END) AS prop_los_ge7,
  -- 14th percentile of LOS
  APPROX_QUANTILES(los_days, 100)[OFFSET(14)] AS los_14th_percentile
FROM
  discharge_groups
WHERE
  discharge_group != 'Other'
GROUP BY
  discharge_group
ORDER BY
  discharge_group;
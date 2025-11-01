WITH first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
stroke_patients AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    p.anchor_age
  FROM first_admissions f
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON f.subject_id = p.subject_id
  WHERE
    f.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE
        d.hadm_id = f.hadm_id
        AND d.icd_version = 10
        AND d.icd_code BETWEEN 'I60' AND 'I69'
    )
),
icu_first_stay AS (
  SELECT
    subject_id,
    hadm_id,
    los / 24.0 AS los_days,  -- Convert hours to days
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
)
SELECT
  APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(25)] AS iqr
FROM stroke_patients s
JOIN icu_first_stay i
  ON s.subject_id = i.subject_id
  AND s.hadm_id = i.hadm_id
  AND i.rn = 1
WHERE i.los_days IS NOT NULL;
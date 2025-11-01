WITH cabg_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON a.hadm_id = pr.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code AND pr.icd_version = dpr.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND LOWER(dpr.long_title) LIKE '%coronary artery bypass%'
),
first_cabg AS (
  SELECT
    subject_id,
    hadm_id,
    admittime
  FROM (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC) AS rn
    FROM cabg_admissions
  )
  WHERE rn = 1
),
icu_los_per_admission AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    SUM(i.los) AS total_icu_los_days
  FROM first_cabg f
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON f.subject_id = i.subject_id
    AND f.hadm_id = i.hadm_id
  GROUP BY f.subject_id, f.hadm_id
)
SELECT
  AVG(total_icu_los_days) AS mean_icu_los_days
FROM icu_los_per_admission;
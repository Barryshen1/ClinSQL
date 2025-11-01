WITH hf_admissions AS (
  -- Identify HF admissions
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (dd.icd_code LIKE '428%' OR dd.icd_code LIKE 'I50%')
    OR LOWER(dd.long_title) LIKE '%heart failure%'
),

eligible_patients AS (
  -- Filter patients: male, age 77–87
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
),

admissions_with_comorbidities AS (
  -- Add CKD and Diabetes flags
  SELECT
    hf.*,
    MAX(CASE WHEN d.icd_code LIKE '585%' OR d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS ckd,
    MAX(CASE WHEN d.icd_code LIKE '250%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%' THEN 1 ELSE 0 END) AS diabetes
  FROM
    hf_admissions hf
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON hf.hadm_id = d.hadm_id
  GROUP BY
    hf.subject_id, hf.hadm_id, hf.admittime, hf.dischtime, hf.hospital_expire_flag, hf.los_days
),

admissions_with_icu_flag AS (
  -- Determine if patient was in ICU on day 1
  SELECT
    a.*,
    MAX(CASE
      WHEN i.intime <= DATETIME_ADD(a.admittime, INTERVAL 1 DAY)
       AND i.outtime >= a.admittime THEN 1
      ELSE 0
    END) AS day1_icu
  FROM
    admissions_with_comorbidities a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, a.los_days, a.ckd, a.diabetes
),

final_cohort AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
      ELSE 'other'
    END AS los_category
  FROM
    admissions_with_icu_flag
  WHERE
    los_days >= 1 AND los_days <= 7 OR los_days >= 8
)

SELECT
  day1_icu,
  los_category,
  COUNT(*) AS n,
  AVG(hospital_expire_flag) * 100 AS in_hosp_mortality_pct,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
  AVG(ckd) * 100 AS ckd_prevalence_pct,
  AVG(diabetes) * 100 AS diabetes_prevalence_pct
FROM
  final_cohort
WHERE
  los_category IN ('1-3', '4-7', '>=8')
GROUP BY
  day1_icu, los_category
ORDER BY
  day1_icu, los_category;
WITH first_admissions AS (
  -- 1. Get each patient's first hospital admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag
  FROM (
    SELECT
      subject_id,
      MIN(admittime) AS first_admittime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY
      subject_id
  ) fa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    a.subject_id = fa.subject_id
    AND a.admittime = fa.first_admittime
),
female_35_45 AS (
  -- 2. Filter for female patients age 35-45
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
),
cabg_first_admissions AS (
  -- 3. From those, keep only first admissions that had a CABG procedure
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag
  FROM
    first_admissions fa
  JOIN
    female_35_45 f
  ON
    fa.subject_id = f.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  ON
    fa.subject_id = pr.subject_id
    AND fa.hadm_id = pr.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
  ON
    pr.icd_code = dp.icd_code
    AND pr.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%coronary artery bypass graft%'
  GROUP BY
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag
)
-- 4. Compute mortality metrics
SELECT
  COUNT(*) AS total_patients,
  SUM(CAST(hospital_expire_flag AS INT64)) AS deaths,
  ROUND(
    SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) * 100,
    2
  ) AS mortality_rate_percent
FROM
  cabg_first_admissions;
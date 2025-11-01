WITH cohort AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 41 AND 51
),

-- 2) Identify CABG ICD procedure codes
cabg_codes AS (
  SELECT
    icd_code,
    icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    LOWER(long_title) LIKE '%coronary%'
    AND LOWER(long_title) LIKE '%bypass%'
),

-- 3) Count distinct CABG procedures per patient (including zeros)
patient_cabg_counts AS (
  SELECT
    c.subject_id,
    COUNT(DISTINCT CASE
      WHEN p.icd_code IS NOT NULL
        AND d.icd_code IS NOT NULL
      THEN p.icd_code
    END) AS cabg_count
  FROM
    cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON c.subject_id = p.subject_id
  LEFT JOIN
    cabg_codes d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  GROUP BY
    c.subject_id
)

-- 4) Compute the standard deviation of CABG counts
SELECT
  STDDEV_POP(cabg_count) AS stddev_cabg_per_patient
FROM
  patient_cabg_counts;
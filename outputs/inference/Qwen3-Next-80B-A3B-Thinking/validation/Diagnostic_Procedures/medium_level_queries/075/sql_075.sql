WITH acs_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%acute coronary syndrome%'
     OR long_title LIKE '%myocardial infarction%'
     OR long_title LIKE '%unstable angina%'
     OR long_title LIKE '%STEMI%'
     OR long_title LIKE '%NSTEMI%'
     OR long_title LIKE '%acute MI%'
),

admissions_with_acs AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND d.seq_num = 1
          AND (d.icd_code, d.icd_version) IN (SELECT icd_code, icd_version FROM acs_codes)
      ) THEN 'primary'
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND (d.icd_code, d.icd_version) IN (SELECT icd_code, icd_version FROM acs_codes)
      ) THEN 'secondary'
      ELSE NULL
    END AS diagnosis_type,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (d.icd_code, d.icd_version) IN (SELECT icd_code, icd_version FROM acs_codes)
    )
),

procedure_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
),

cohort AS (
  SELECT
    a.hadm_id,
    a.diagnosis_type,
    a.los_days,
    COALESCE(p.num_procedures, 0) AS num_procedures,
    CASE
      WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_category
  FROM admissions_with_acs a
  LEFT JOIN procedure_counts p ON a.hadm_id = p.hadm_id
)

SELECT
  los_category,
  diagnosis_type,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY num_procedures) AS p25,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY num_procedures) AS p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY num_procedures) AS p75
FROM cohort
WHERE los_category IS NOT NULL
  AND diagnosis_type IS NOT NULL
GROUP BY los_category, diagnosis_type;
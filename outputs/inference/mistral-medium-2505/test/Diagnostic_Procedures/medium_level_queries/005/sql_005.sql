WITH ischemic_stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS stay_duration_days,
    d.seq_num AS diagnosis_seq_num
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND d.icd_code LIKE 'I63%'
),

procedure_counts AS (
  SELECT
    isa.hadm_id,
    isa.stay_duration_days,
    isa.diagnosis_seq_num,
    COUNT(p.icd_code) AS procedure_count
  FROM
    ischemic_stroke_admissions isa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON isa.subject_id = p.subject_id AND isa.hadm_id = p.hadm_id
  GROUP BY
    isa.hadm_id, isa.stay_duration_days, isa.diagnosis_seq_num
),

duration_categories AS (
  SELECT
    hadm_id,
    stay_duration_days,
    diagnosis_seq_num,
    procedure_count,
    CASE
      WHEN stay_duration_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN stay_duration_days BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL
    END AS duration_category
  FROM
    procedure_counts
)

SELECT
  duration_category,
  CASE
    WHEN diagnosis_seq_num = 1 THEN 'Primary diagnosis'
    ELSE 'Secondary diagnosis'
  END AS diagnosis_type,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(procedure_count) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures
FROM
  duration_categories
WHERE
  duration_category IS NOT NULL
GROUP BY
  duration_category, diagnosis_type
ORDER BY
  duration_category, diagnosis_type;
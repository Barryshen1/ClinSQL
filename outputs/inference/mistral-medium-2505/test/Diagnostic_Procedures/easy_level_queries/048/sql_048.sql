WITH male_patients_52_62 AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),

valve_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_valve_procedures
  FROM
    male_patients_52_62 p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.hadm_id = pr.hadm_id
  WHERE
    -- Filter for valve repair/replacement ICD codes (example: 35.1*, 35.2*)
    -- Adjust these codes based on actual MIMIC-IV data
    pr.icd_code LIKE '35.1%' OR pr.icd_code LIKE '35.2%'
  GROUP BY
    p.subject_id,
    p.hadm_id
),

procedure_counts AS (
  SELECT
    distinct_valve_procedures
  FROM
    valve_procedures
)

SELECT
  PERCENTILE_CONT(distinct_valve_procedures, 0.25) OVER() AS q1,
  PERCENTILE_CONT(distinct_valve_procedures, 0.5) OVER() AS median,
  PERCENTILE_CONT(distinct_valve_procedures, 0.75) OVER() AS q3,
  -- Calculate IQR (Q3 - Q1)
  PERCENTILE_CONT(distinct_valve_procedures, 0.75) OVER() -
    PERCENTILE_CONT(distinct_valve_procedures, 0.25) OVER() AS iqr
FROM
  procedure_counts
LIMIT 1;
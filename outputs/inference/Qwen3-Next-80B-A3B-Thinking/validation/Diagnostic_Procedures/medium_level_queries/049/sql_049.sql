WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 87 AND 97
),
sepsis_admissions AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%')
    AND hadm_id NOT IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code = 'R65.21'
    )
  GROUP BY hadm_id
),
los_data AS (
  SELECT
    pa.hadm_id,
    DATE_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days
  FROM patient_admissions pa
  JOIN sepsis_admissions sa
    ON pa.hadm_id = sa.hadm_id
  WHERE DATE_DIFF(pa.dischtime, pa.admittime, DAY) BETWEEN 1 AND 7
),
procedures_count AS (
  SELECT
    hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
)
SELECT
  CASE
    WHEN los.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los.los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  AVG(pc.procedure_count) AS mean_procedures
FROM los_data los
JOIN procedures_count pc
  ON los.hadm_id = pc.hadm_id
GROUP BY los_group
HAVING los_group IS NOT NULL;
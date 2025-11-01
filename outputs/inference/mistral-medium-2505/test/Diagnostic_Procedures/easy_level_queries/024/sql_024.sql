WITH female_patients_58_68 AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    -- Approximate age at admission (anchor_age is age at anchor_year)
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 58 AND 68
),

coronary_procedures AS (
  SELECT
    fp.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_coronary_procedures
  FROM
    female_patients_58_68 fp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  ON
    fp.hadm_id = pr.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    pr.icd_code = d.icd_code
    AND pr.icd_version = d.icd_version
  WHERE
    -- Filter for coronary angiography/PCI procedures (example ICD-9/10 codes)
    (pr.icd_version = 9 AND pr.icd_code LIKE '36.0%') OR
    (pr.icd_version = 9 AND pr.icd_code = '00.66') OR
    (pr.icd_version = 10 AND pr.icd_code LIKE '027U3KZ%')
  GROUP BY
    fp.hadm_id
)

SELECT
  PERCENTILE_CONT(distinct_coronary_procedures, 0.75) OVER() AS percentile_75
FROM
  coronary_procedures
LIMIT 1;
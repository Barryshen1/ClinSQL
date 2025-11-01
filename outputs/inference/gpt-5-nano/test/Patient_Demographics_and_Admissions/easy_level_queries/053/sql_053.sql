WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
    AND a.dischtime IS NOT NULL
),
aki AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id
  WHERE (di.icd_version = 9 AND di.icd_code LIKE '584%')
     OR (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
),
cohort_aki AS (
  SELECT c.*
  FROM cohort c
  JOIN aki k ON c.hadm_id = k.hadm_id
),
readmit_flag AS (
  SELECT ca.hadm_id,
         CASE WHEN EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.admissions` nb
           WHERE nb.subject_id = ca.subject_id
             AND nb.admittime > ca.dischtime
             AND nb.admittime <= TIMESTAMP_ADD(ca.dischtime, INTERVAL 30 DAY)
         )
         THEN 1 ELSE 0 END AS readmit_30
  FROM cohort_aki ca
)
SELECT STDDEV_POP(readmit_30) AS stddev_30day_readmission
FROM readmit_flag;
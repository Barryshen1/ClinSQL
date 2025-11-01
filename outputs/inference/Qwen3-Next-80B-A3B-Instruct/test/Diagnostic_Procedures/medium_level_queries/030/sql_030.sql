WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),
ugib_admissions AS (
  SELECT DISTINCT
    fa.hadm_id,
    fa.los_days
  FROM
    filtered_admissions fa
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON fa.hadm_id = di.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON di.icd_code = did.icd_code
    AND di.icd_version = did.icd_version
  WHERE
    LOWER(did.long_title) LIKE '%upper gastrointestinal hemorrhage%'
    OR LOWER(did.long_title) LIKE '%upper gi bleeding%'
    OR LOWER(did.long_title) LIKE '%gastric hemorrhage%'
    OR LOWER(did.long_title) LIKE '%esophageal hemorrhage%'
    OR LOWER(did.long_title) LIKE '%duodenal hemorrhage%'
    OR LOWER(did.long_title) LIKE '%peptic ulcer hemorrhage%'
    OR LOWER(did.long_title) LIKE '%gastrointestinal bleeding%'
    OR LOWER(did.long_title) LIKE '%hemorrhage from upper gi tract%'
    OR LOWER(did.long_title) LIKE '%hemorrhage of upper gastrointestinal tract%'
    OR LOWER(did.long_title) LIKE '%hemorrhage of stomach%'
    OR LOWER(did.long_title) LIKE '%hemorrhage of duodenum%'
    OR LOWER(did.long_title) LIKE '%hemorrhage of esophagus%'
    OR LOWER(did.long_title) LIKE '%hemorrhage of upper gi%'
    OR LOWER(did.long_title) LIKE '%upper gi hemorrhage%'
    OR LOWER(did.long_title) LIKE '%acute upper gi bleeding%'
    OR LOWER(did.long_title) LIKE '%acute upper gastrointestinal bleeding%'
),
procedure_counts AS (
  SELECT
    ua.hadm_id,
    ua.los_days,
    COUNT(pi.seq_num) AS num_procedures
  FROM
    ugib_admissions ua
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd pi
    ON ua.hadm_id = pi.hadm_id
  GROUP BY
    ua.hadm_id, ua.los_days
),
binned_procedures AS (
  SELECT
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group,
    num_procedures
  FROM
    procedure_counts
)
SELECT
  los_group,
  APPROX_QUANTILES(num_procedures, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(num_procedures, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(num_procedures, 4)[OFFSET(3)] AS p75
FROM
  binned_procedures
GROUP BY
  los_group
ORDER BY
  los_group;
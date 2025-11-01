with sepsis but without septic shock, stratified by LOS 1-3 vs 4-7 days.
WITH sepsis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- restrict to LOS 1-7 days (we will split into 1-3 and 4-7 later)
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    -- must have at least one diagnosis mentioning "sepsis"
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      USING(icd_code, icd_version)
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%sepsis%'
    )
    -- must NOT have any diagnosis mentioning "septic shock"
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      USING(icd_code, icd_version)
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%septic shock%'
    )
),

procedures_per_adm AS (
  SELECT
    hadm_id,
    COUNT(*) AS n_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY
    hadm_id
)

SELECT
  CASE
    WHEN s.los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN s.los_days BETWEEN 4 AND 7 THEN '4-7'
    ELSE 'other'
  END AS los_cohort,
  COUNT(1) AS admissions_n,
  ROUND(AVG(COALESCE(p.n_procedures, 0)), 3) AS mean_procedures_per_admission
FROM
  sepsis_admissions s
LEFT JOIN
  procedures_per_adm p
USING(hadm_id)
GROUP BY
  los_cohort
ORDER BY
  los_cohort;
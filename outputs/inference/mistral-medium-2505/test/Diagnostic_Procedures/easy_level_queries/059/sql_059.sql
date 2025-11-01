WITH male_patients_76_86 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 76 AND 86
),

cardiac_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.icd_code) AS distinct_cardiac_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE
    p.subject_id IN (SELECT subject_id FROM male_patients_76_86)
    AND (
      LOWER(d.long_title) LIKE '%cardiac%'
      OR LOWER(d.long_title) LIKE '%heart%'
    )
  GROUP BY
    p.subject_id, p.hadm_id
),

all_hospitalizations AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COALESCE(cp.distinct_cardiac_procedures, 0) AS distinct_cardiac_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    male_patients_76_86 mp ON a.subject_id = mp.subject_id
  LEFT JOIN
    cardiac_procedures cp ON a.subject_id = cp.subject_id AND a.hadm_id = cp.hadm_id
)

SELECT
  PERCENTILE_CONT(distinct_cardiac_procedures, 0.25) OVER() AS q1,
  PERCENTILE_CONT(distinct_cardiac_procedures, 0.75) OVER() AS q3,
  PERCENTILE_CONT(distinct_cardiac_procedures, 0.75) OVER() - PERCENTILE_CONT(distinct_cardiac_procedures, 0.25) OVER() AS iqr
FROM
  all_hospitalizations
LIMIT 1;
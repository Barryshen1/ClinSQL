WITH female_82_92 AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
),
cardiac_procedures AS (
  SELECT
    dp.icd_code,
    dp.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
  WHERE
    LOWER(dp.long_title) LIKE '%cardiac%'
    OR LOWER(dp.long_title) LIKE '%heart%'
    OR LOWER(dp.long_title) LIKE '%coronary%'
    OR LOWER(dp.long_title) LIKE '%cardio%'
    OR LOWER(dp.long_title) LIKE '%valve%'
    OR LOWER(dp.long_title) LIKE '%aorta%'
    OR LOWER(dp.long_title) LIKE '%pacemaker%'
),
hadm_cardiac_proc_count AS (
  SELECT
    f.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS num_distinct_cardiac_procs
  FROM
    female_82_92 f
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      ON f.hadm_id = pr.hadm_id
    LEFT JOIN cardiac_procedures cp
      ON pr.icd_code = cp.icd_code AND pr.icd_version = cp.icd_version
  WHERE
    cp.icd_code IS NOT NULL
  GROUP BY
    f.hadm_id
)
SELECT
  PERCENTILE_CONT(num_distinct_cardiac_procs, 0.25) OVER() AS percentile_25th
FROM
  hadm_cardiac_proc_count
;
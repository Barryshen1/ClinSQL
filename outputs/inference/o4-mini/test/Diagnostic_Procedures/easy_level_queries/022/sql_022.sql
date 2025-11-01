WITH filtered_hadm AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
),

pacemaker_procs AS (
  SELECT
    pi.hadm_id,
    pi.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dp
      ON pi.icd_version = dp.icd_version
     AND pi.icd_code = dp.icd_code
  WHERE
    LOWER(dp.long_title) LIKE '%pacemaker%'
    OR LOWER(dp.long_title) LIKE '%implant%'
),

hadm_proc_counts AS (
  SELECT
    fh.hadm_id,
    COUNT(DISTINCT pp.icd_code) AS num_distinct_proc
  FROM
    filtered_hadm AS fh
    LEFT JOIN pacemaker_procs AS pp
      ON fh.hadm_id = pp.hadm_id
  GROUP BY
    fh.hadm_id
)

SELECT
  MIN(num_distinct_proc) AS min_distinct_pacemaker_icd_procs_per_hadm
FROM
  hadm_proc_counts;
WITH pacemaker_icd_procs AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.icd_code,
    pr.icd_version,
    d.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pr.icd_code = d.icd_code
   AND pr.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND (
      LOWER(d.long_title) LIKE '%pacemaker%'
      OR LOWER(d.long_title) LIKE '%defibrillator%'
      OR LOWER(d.long_title) LIKE '%cardioverter%'
      OR LOWER(d.long_title) LIKE '%icd%'
    )
),
counts_per_hadm AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS distinct_proc_count
  FROM pacemaker_icd_procs
  GROUP BY hadm_id
)
SELECT
  MIN(distinct_proc_count) AS min_distinct_pacemaker_icd_proc_per_hadm
FROM counts_per_hadm;
WITH female_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
),

-- Identify and dedupe coronary angiography/PCI procedures per admission
angiography_pci AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    pi.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
      ON pi.icd_code = dicd.icd_code
     AND pi.icd_version = dicd.icd_version
  WHERE
    LOWER(dicd.long_title) LIKE '%coronary%'
    AND (
      LOWER(dicd.long_title) LIKE '%angiograph%'
      OR LOWER(dicd.long_title) LIKE '%percutaneous%'
      OR LOWER(dicd.long_title) LIKE '%pci%'
    )
  GROUP BY
    pi.subject_id,
    pi.hadm_id,
    pi.icd_code
),

-- Count distinct procedures per admission (zero if none)
proc_counts AS (
  SELECT
    fc.subject_id,
    fc.hadm_id,
    COALESCE(count(ap.icd_code), 0) AS proc_count
  FROM
    female_cohort fc
    LEFT JOIN angiography_pci ap
      ON fc.subject_id = ap.subject_id
     AND fc.hadm_id = ap.hadm_id
  GROUP BY
    fc.subject_id,
    fc.hadm_id
)

-- Compute the 75th percentile of distinct procedure counts
SELECT
  APPROX_QUANTILES(proc_count, 4)[OFFSET(3)] AS p75_distinct_coronary_procs
FROM
  proc_counts;
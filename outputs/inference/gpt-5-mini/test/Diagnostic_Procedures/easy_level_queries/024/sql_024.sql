WITH cohort_admissions AS (
  -- female patients age 58-68 with their admissions
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
  WHERE
    LOWER(p.gender) = 'female'
    AND p.anchor_age BETWEEN 58 AND 68
),

proc_icd AS (
  -- ICD procedure codes whose description likely indicates coronary angiography / PCI
  SELECT
    pi.subject_id,
    pi.hadm_id,
    pi.chartdate,
    CONCAT('ICDPROC_', pi.icd_code) AS proc_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dic
      ON pi.icd_code = dic.icd_code
      AND pi.icd_version = dic.icd_version
  WHERE
    -- keyword-based matching on the long_title; fall back to matching icd_code if needed
    (
      LOWER(COALESCE(dic.long_title, '')) LIKE '%coronar%'
      OR LOWER(COALESCE(dic.long_title, '')) LIKE '%angiograph%'
      OR LOWER(COALESCE(dic.long_title, '')) LIKE '%angiogram%'
      OR LOWER(COALESCE(dic.long_title, '')) LIKE '%percutan%'
      OR LOWER(COALESCE(dic.long_title, '')) LIKE '%pci%'
      OR LOWER(COALESCE(dic.long_title, '')) LIKE '%stent%'
    )
),

proc_hcpcs AS (
  -- HCPCS/CPT billing events that likely correspond to coronary angiography / PCI
  SELECT
    h.subject_id,
    h.hadm_id,
    h.chartdate,
    CONCAT('HCPCS_', h.hcpcs_cd) AS proc_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
      ON h.hcpcs_cd = dh.code
  WHERE
    (
      LOWER(COALESCE(dh.long_description, '')) LIKE '%coronar%'
      OR LOWER(COALESCE(dh.long_description, '')) LIKE '%angiograph%'
      OR LOWER(COALESCE(dh.long_description, '')) LIKE '%angiogram%'
      OR LOWER(COALESCE(dh.long_description, '')) LIKE '%percutan%'
      OR LOWER(COALESCE(dh.long_description, '')) LIKE '%pci%'
      OR LOWER(COALESCE(dh.long_description, '')) LIKE '%stent%'
      OR LOWER(COALESCE(dh.short_description, '')) LIKE '%coronar%'
      OR LOWER(COALESCE(dh.short_description, '')) LIKE '%angiograph%'
      OR LOWER(COALESCE(dh.short_description, '')) LIKE '%angiogram%'
      OR LOWER(COALESCE(dh.short_description, '')) LIKE '%percutan%'
      OR LOWER(COALESCE(dh.short_description, '')) LIKE '%pci%'
      OR LOWER(COALESCE(dh.short_description, '')) LIKE '%stent%'
    )
),

all_proc_events AS (
  -- union of the two procedure sources
  SELECT * FROM proc_icd
  UNION ALL
  SELECT * FROM proc_hcpcs
),

proc_events_within_admission AS (
  -- keep only procedure events that occur during the matching admission period for cohort admissions
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ape.proc_code
  FROM
    cohort_admissions ca
    LEFT JOIN all_proc_events ape
      ON ca.hadm_id = ape.hadm_id
      AND DATE(ape.chartdate) BETWEEN DATE(ca.admittime) AND DATE(ca.dischtime)
  -- note: LEFT JOIN so admissions without any matching events remain (proc_code will be NULL)
),

per_admission_counts AS (
  -- count distinct procedure codes per admission (distinct by proc_code)
  SELECT
    hadm_id,
    subject_id,
    COALESCE(COUNT(DISTINCT proc_code), 0) AS proc_count
  FROM
    proc_events_within_admission
  GROUP BY
    hadm_id,
    subject_id
)

-- compute the 75th percentile (approximate) across admissions in the cohort
SELECT
  -- APPROX_QUANTILES returns an array of 101 elements (0..100). OFFSET 75 is the 75th percentile.
  (SELECT quantiles[OFFSET(75)]
   FROM (
     SELECT APPROX_QUANTILES(proc_count, 100) AS quantiles
     FROM per_admission_counts
   )
  ) AS p75_distinct_coronary_angiography_pci_per_admission,
  -- also return number of admissions in cohort for context
  (SELECT COUNT(*) FROM per_admission_counts) AS admissions_in_cohort
;
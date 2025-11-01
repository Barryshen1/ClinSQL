WITH valve_procs AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    pr.icd_code,
    dip.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      USING (subject_id, hadm_id)
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
      ON pr.icd_code = dip.icd_code
      AND pr.icd_version = dip.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND dip.long_title IS NOT NULL
    -- require 'valve' and any of the repair/replacement related keywords
    AND LOWER(dip.long_title) LIKE '%valve%'
    AND (
      LOWER(dip.long_title) LIKE '%repair%'
      OR LOWER(dip.long_title) LIKE '%replace%'
      OR LOWER(dip.long_title) LIKE '%replacement%'
      OR LOWER(dip.long_title) LIKE '%valvuloplasty%'
      OR LOWER(dip.long_title) LIKE '%valvotomy%'
      OR LOWER(dip.long_title) LIKE '%prosthesis%'
    )
),

per_admission_counts AS (
  -- count distinct procedure codes (distinct valve repair/replacement procedure types) per hospital admission
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_distinct_valve_procs
  FROM valve_procs
  GROUP BY hadm_id
)

-- return the minimum number among admissions that had at least one valve repair/replacement procedure
SELECT
  MIN(num_distinct_valve_procs) AS min_distinct_valve_repair_replacement_procs_per_hadm
FROM per_admission_counts;
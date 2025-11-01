WITH
  -- Step 1: Identify all ICD codes related to mechanical circulatory support procedures
  mech_circ_support_codes AS (
    SELECT
      DISTINCT d.icd_code,
      d.icd_version
    FROM
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    WHERE
      -- Keywords for mechanical circulatory support devices (case-insensitive search)
      LOWER(d.long_title) LIKE '%intra-aortic balloon%'
      OR LOWER(d.long_title) LIKE '%heart assist system%'
      OR LOWER(d.long_title) LIKE '%assist device%'
      OR LOWER(d.long_title) LIKE '%cardiac pump%'
      OR LOWER(d.long_title) LIKE '%extracorporeal membrane oxygenation%' -- ECMO
      OR LOWER(d.long_title) LIKE '%ecmo%'
      OR LOWER(d.long_title) LIKE '%ventricular assist%' -- e.g., LVAD/RVAD
      OR LOWER(d.long_title) LIKE '%circulatory support%'
  ),
  -- Step 2: Filter patients by specified demographics (female, anchor_age 86-96)
  filtered_patients AS (
    SELECT
      p.subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 86 AND 96
  ),
  -- Step 3: Count distinct mechanical circulatory support procedures per hospitalization for the filtered patients
  procedures_per_hadm AS (
    SELECT
      pi.subject_id,
      pi.hadm_id,
      COUNT(DISTINCT pi.icd_code) AS num_distinct_procedures
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    INNER JOIN
      filtered_patients fp
      ON pi.subject_id = fp.subject_id
    INNER JOIN
      mech_circ_support_codes mcsc
      ON pi.icd_code = mcsc.icd_code
      AND pi.icd_version = mcsc.icd_version
    GROUP BY
      pi.subject_id,
      pi.hadm_id
  )
-- Step 4: Calculate the Q1, Q3, and Interquartile Range (IQR)
SELECT
  PERCENTILE_CONT(t.num_distinct_procedures, 0.25) OVER() AS q1_procedures_per_hadm,
  PERCENTILE_CONT(t.num_distinct_procedures, 0.75) OVER() AS q3_procedures_per_hadm,
  (PERCENTILE_CONT(t.num_distinct_procedures, 0.75) OVER() - PERCENTILE_CONT(t.num_distinct_procedures, 0.25) OVER()) AS iqr_procedures_per_hadm
FROM
  procedures_per_hadm t
QUALIFY ROW_NUMBER() OVER() = 1 -- Ensures only one row of aggregated results is returned
;
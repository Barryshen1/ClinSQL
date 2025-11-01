WITH PatientProcedureCounts AS (
  -- Step 1: Count the number of distinct relevant procedures for each patient in the cohort
  SELECT
    pat.subject_id,
    COUNT(DISTINCT proc.icd_code) AS num_distinct_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON pat.subject_id = proc.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
    ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
  WHERE
    -- Filter for the patient demographic: men aged 75-85
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 75 AND 85
    -- Filter for the procedures of interest by their description
    AND (
      LOWER(d_proc.long_title) LIKE '%catheter ablation%'
      OR LOWER(d_proc.long_title) LIKE '%cardioversion%'
    )
  GROUP BY
    pat.subject_id
)
-- Step 2: Calculate the Interquartile Range (IQR) of the counts from the above CTE
SELECT
  -- APPROX_QUANTILES returns an array [min, q1, median, q3, max] for n=4
  -- IQR is the difference between the 3rd quartile (index 3) and the 1st quartile (index 1)
  (
    APPROX_QUANTILES(ppc.num_distinct_procedures, 4)[OFFSET(3)]
    - APPROX_QUANTILES(ppc.num_distinct_procedures, 4)[OFFSET(1)]
  ) AS iqr_of_distinct_procedures
FROM
  PatientProcedureCounts AS ppc;
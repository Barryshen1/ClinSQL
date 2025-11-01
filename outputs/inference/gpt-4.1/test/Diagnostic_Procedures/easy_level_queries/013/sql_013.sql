SELECT
  MIN(valve_proc_count) AS min_distinct_valve_procs_per_hospitalization
FROM (
  SELECT
    proc.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS valve_proc_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON proc.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
      ON proc.icd_code = dicd.icd_code
      AND proc.icd_version = dicd.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 57 AND 67
    AND (
      LOWER(dicd.long_title) LIKE '%valve repair%'
      OR LOWER(dicd.long_title) LIKE '%valve replacement%'
    )
  GROUP BY
    proc.hadm_id
);
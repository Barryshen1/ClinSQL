WITH valve_procs_per_admission AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT pi.icd_code) AS cnt_valve_procs
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
      ON a.subject_id = pi.subject_id
     AND a.hadm_id    = pi.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
      ON pi.icd_code    = d.icd_code
     AND pi.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND REGEXP_CONTAINS(
          LOWER(d.long_title),
          r'valve.*(repair|replacement|repl)'
        )
  GROUP BY
    a.hadm_id
  HAVING
    COUNT(DISTINCT pi.icd_code) > 0
)
SELECT
  MIN(cnt_valve_procs) AS min_distinct_valve_procedures_per_admission
FROM
  valve_procs_per_admission;
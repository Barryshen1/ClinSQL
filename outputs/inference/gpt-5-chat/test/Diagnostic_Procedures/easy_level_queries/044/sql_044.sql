WITH mcs_patients AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS num_distinct_mcs_procs
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON p.subject_id = proc.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
    AND (
      UPPER(dproc.long_title) LIKE '%CIRCULATORY SUPPORT%'
      OR UPPER(dproc.long_title) LIKE '%VENTRICULAR ASSIST%'
      OR UPPER(dproc.long_title) LIKE '%MECHANICAL ASSIST%'
      OR UPPER(dproc.long_title) LIKE '%ECMO%'
      OR UPPER(dproc.long_title) LIKE '%EXTRACORPOREAL MEMBRANE%'
    )
  GROUP BY
    p.subject_id
)
SELECT
  STDDEV_SAMP(num_distinct_mcs_procs) AS sd_distinct_mcs_procs
FROM
  mcs_patients;
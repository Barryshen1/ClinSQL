SELECT
  STDDEV_POP(procedure_count) AS sd_distinct_mechanical_support_procs_per_patient
FROM (
  SELECT
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
      ON a.subject_id = proc.subject_id
      AND a.hadm_id    = proc.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dp
      ON proc.icd_code    = dp.icd_code
      AND proc.icd_version = dp.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
    AND (
      LOWER(dp.long_title) LIKE '%assist%'
      OR LOWER(dp.long_title) LIKE '%ecmo%'
      OR LOWER(dp.long_title) LIKE '%balloon%'
    )
  GROUP BY
    p.subject_id
)
;
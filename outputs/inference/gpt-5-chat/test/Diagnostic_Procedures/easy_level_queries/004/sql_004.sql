WITH cabg_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT CONCAT(proc.icd_code, '-', proc.icd_version)) AS distinct_cabg_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
    AND LOWER(dproc.long_title) LIKE '%cabg%'
  GROUP BY
    p.subject_id
)
SELECT
  STDDEV(distinct_cabg_count) AS sd_distinct_cabg_per_patient
FROM
  cabg_counts;
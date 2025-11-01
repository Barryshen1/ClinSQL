WITH cabg_counts AS (
  SELECT
    p.subject_id,
    COUNT(*) AS cabg_procedure_count
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd pi
    ON p.subject_id = pi.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
    ON pi.icd_code = dip.icd_code
    AND pi.icd_version = dip.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND UPPER(dip.long_title) LIKE '%CABG%'
  GROUP BY
    p.subject_id
)
SELECT
  PERCENTILE_CONT(cabg_procedure_count, 0.25) OVER () AS percentile_25th
FROM
  cabg_counts
LIMIT 1;
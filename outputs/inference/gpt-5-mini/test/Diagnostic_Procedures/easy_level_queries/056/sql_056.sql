WITH mcs_counts AS (
  -- aggregate distinct MCS procedure codes per patient
  SELECT
    proc.subject_id,
    COUNT(DISTINCT proc.icd_code) AS mcs_proc_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
  ON
    proc.icd_code = d.icd_code
    AND proc.icd_version = d.icd_version
  WHERE
    (
      LOWER(d.long_title) LIKE '%ecmo%' OR
      LOWER(d.long_title) LIKE '%extracorporeal membrane%' OR
      LOWER(d.long_title) LIKE '%intra-aortic balloon%' OR
      LOWER(d.long_title) LIKE '%intra aortic%' OR
      LOWER(d.long_title) LIKE '%ventricular assist%' OR
      LOWER(d.long_title) LIKE '%left ventricular assist%' OR
      LOWER(d.long_title) LIKE '%mechanical circulatory support%' OR
      LOWER(d.long_title) LIKE '%implantable cardiac assist%' OR
      LOWER(d.long_title) LIKE '%impella%'
    )
  GROUP BY
    proc.subject_id
)

SELECT
  -- APPROX_QUANTILES(...,4) returns [min, 25th, 50th, 75th, max], so OFFSET(1) is the 25th percentile
  APPROX_QUANTILES(COALESCE(mc.mcs_proc_count, 0), 4)[OFFSET(1)] AS mcs_procedure_25th_percentile
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
LEFT JOIN
  mcs_counts AS mc
ON
  p.subject_id = mc.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 43 AND 53;
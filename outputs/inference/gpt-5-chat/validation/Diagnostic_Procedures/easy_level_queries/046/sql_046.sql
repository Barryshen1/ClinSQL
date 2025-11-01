WITH mec_support AS (
  SELECT
    p.subject_id,
    pr.icd_code,
    pr.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
   AND pr.icd_version = dp.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND (
      LOWER(dp.long_title) LIKE '%mechanical circulatory support%'
      OR LOWER(dp.long_title) LIKE '%ventricular assist%'
      OR LOWER(dp.long_title) LIKE '%extracorporeal membrane oxygenation%'
      OR LOWER(dp.long_title) LIKE '%ecmo%'
      OR LOWER(dp.long_title) LIKE '%intra-aortic balloon pump%'
    )
)
SELECT
  MAX(proc_count) AS max_distinct_mech_support_per_patient
FROM (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS proc_count
  FROM mec_support
  GROUP BY subject_id
);
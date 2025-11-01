WITH mcs_counts AS (
  SELECT 
    pi.subject_id, 
    COUNT(DISTINCT pi.icd_code) AS num_distinct_mcs
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pi.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
    AND (
      LOWER(dip.long_title) LIKE '%heart assist%'
      OR LOWER(dip.long_title) LIKE '%ventricular assist%'
      OR LOWER(dip.long_title) LIKE '%mechanical circulatory%'
      OR LOWER(dip.long_title) LIKE '%aortic balloon%'
      OR LOWER(dip.long_title) LIKE '%extracorporeal membrane%'
    )
  GROUP BY 
    pi.subject_id
)
SELECT 
  STDDEV(num_distinct_mcs) AS sd_distinct_mcs_procedures
FROM 
  mcs_counts;
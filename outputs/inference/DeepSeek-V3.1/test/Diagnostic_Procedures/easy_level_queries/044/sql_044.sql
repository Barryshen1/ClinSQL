WITH mcs_procedures AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_mcs_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    ON proc.icd_code = dicd.icd_code 
    AND proc.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
    AND (
      dicd.long_title LIKE '%balloon pump%' 
      OR dicd.long_title LIKE '%assist device%'
      OR dicd.long_title LIKE '%mechanical support%'
      OR dicd.long_title LIKE '%heart assist%'
    )
  GROUP BY p.subject_id
)

SELECT 
  STDDEV(distinct_mcs_count) AS sd_distinct_mcs_procedures
FROM mcs_procedures;